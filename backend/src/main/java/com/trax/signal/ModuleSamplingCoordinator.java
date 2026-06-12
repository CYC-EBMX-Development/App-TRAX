package com.trax.signal;

import com.trax.model.RideRecord;
import com.trax.model.Trail;
import com.trax.repository.RideRecordRepository;
import com.trax.util.GeoUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Backend-driven adaptive sampling for TRAX modules.
 *
 * <p>Mirrors the App's finish-line "fast mode" engine
 * ({@code ActiveRideService._decideSamplingMode}) but runs server-side on
 * the module-telemetry ingest path, so it works regardless of whether the
 * rider's phone is foregrounded or even listening. When a module rider on a
 * trail/race ride approaches the finish line it boosts the module to 5 Hz;
 * once they cross and leave the zone it reverts to the default 1 Hz.
 *
 * <p>Denser sampling near the line makes the recorded crossing instant
 * (the lap {@code end_time} derived from the GPS point) more precise, which
 * directly improves the time-based race finish ranking.
 *
 * <p>Same decision constants as the App: speed-tiered trigger radius
 * (25 m below 50 km/h, 50 m at/above), +8 m exit hysteresis, and
 * approach-only entry (distance must be shrinking) so the fast cadence only
 * kicks in on the way TOWARDS the line, not while leaving it.
 *
 * <p>No online pre-check is needed before sending a command: a sampling
 * decision is only ever made from a freshly-received GPS fix, so the device
 * is provably online at that moment. A {@link #watchdog()} sweeps any device
 * stuck at 5 Hz back to 1 Hz once it is no longer in the finish zone (left
 * the zone, GPS fixes stopped arriving, or the ride ended) so a module can
 * never be left at 5 Hz indefinitely.
 */
@Service
public class ModuleSamplingCoordinator {
    private static final Logger log = LoggerFactory.getLogger(ModuleSamplingCoordinator.class);

    private static final double FAST_SPEED_THRESHOLD_KMH = 50.0;
    private static final double FAST_RADIUS_LOW_SPEED_M = 25.0;
    private static final double FAST_RADIUS_HIGH_SPEED_M = 50.0;
    private static final double FAST_EXIT_HYSTERESIS_M = 8.0;
    /** Distance beyond which the watchdog considers a device to have left the
     *  finish zone (widest trigger radius + exit hysteresis). */
    private static final double WATCHDOG_EXIT_RADIUS_M =
            FAST_RADIUS_HIGH_SPEED_M + FAST_EXIT_HYSTERESIS_M; // 58 m
    /** If no fresh fix has arrived from a 5 Hz device within this window, it
     *  is no longer actively approaching the line — revert to 1 Hz. At 5 Hz a
     *  fix is expected every ~200 ms, so several seconds of silence means the
     *  rider stopped, went offline, or the ride ended. */
    private static final long FAST_STALE_TIMEOUT_MS = 8_000L;

    private final RideRecordRepository rideRepository;
    private final ModuleCommandService commandService;

    /** Per-device fast/base state, keyed by module serial. */
    private final ConcurrentHashMap<String, DeviceState> states = new ConcurrentHashMap<>();

    public ModuleSamplingCoordinator(RideRecordRepository rideRepository,
                                     ModuleCommandService commandService) {
        this.rideRepository = rideRepository;
        this.commandService = commandService;
    }

    /**
     * Feed one module GPS fix. Loads the covering ride; only trail-based
     * lap/race rides that are still active drive sampling decisions.
     *
     * @param serial   module serial (== downlink topic prefix)
     * @param rideId   id of the ride this fix was ingested into
     * @param lat      fix latitude (decimal degrees)
     * @param lon      fix longitude
     * @param speedKmh module speed (km/h)
     */
    @Transactional(readOnly = true)
    public void onModuleFix(String serial, Long rideId, double lat, double lon, double speedKmh) {
        if (serial == null || rideId == null) return;
        try {
            RideRecord ride = rideRepository.findById(rideId).orElse(null);
            if (ride == null || !"active".equals(ride.getStatus())) return;
            if (ride.getTargetLaps() == null || ride.getTargetLaps() <= 0) return;
            Trail trail = ride.getTrail();
            if (trail == null || trail.getStartLatitude() == null || trail.getStartLongitude() == null) {
                return;
            }
            decide(serial, rideId, lat, lon, speedKmh,
                    trail.getStartLatitude(), trail.getStartLongitude());
        } catch (Exception e) {
            log.warn("onModuleFix failed serial={} ride={} err={}", serial, rideId, e.toString());
        }
    }

    /**
     * Current sampling mode for a device. {@code true} = 5 Hz fast mode
     * (near finish line), {@code false} = 1 Hz baseline (or unknown device).
     * Used by {@code CtrlIngestService} to throttle ctrl persistence to the
     * same cadence as GPS without sending any extra downlink command.
     */
    public boolean isFast(String serial) {
        if (serial == null) return false;
        DeviceState st = states.get(serial);
        if (st == null) return false;
        synchronized (st) {
            return st.fast;
        }
    }

    /** Forget a device's state and ensure it is back at the default 1 Hz. */
    public void resetToBase(String serial) {
        if (serial == null) return;
        DeviceState st = states.remove(serial);
        if (st != null) {
            synchronized (st) {
                if (st.fast) commandService.setSamplingHz(serial, 1);
            }
        }
    }

    private void decide(String serial, Long rideId, double lat, double lon, double speedKmh,
                        double finishLat, double finishLon) {
        double speed = Math.max(0.0, Math.min(200.0, speedKmh));
        double triggerR = speed >= FAST_SPEED_THRESHOLD_KMH
                ? FAST_RADIUS_HIGH_SPEED_M : FAST_RADIUS_LOW_SPEED_M;
        double exitR = triggerR + FAST_EXIT_HYSTERESIS_M;
        double distM = GeoUtils.haversineKm(lat, lon, finishLat, finishLon) * 1000.0;

        DeviceState st = states.computeIfAbsent(serial, k -> new DeviceState());
        synchronized (st) {
            st.rideId = rideId;
            st.lastFixAtMs = System.currentTimeMillis();

            boolean approaching = distM <= triggerR
                    && (st.lastDistM == null || distM < st.lastDistM);
            boolean leaving = st.lastDistM != null && distM > st.lastDistM;
            st.lastDistM = distM;

            boolean desiredFast = st.fast;
            if (approaching) {
                desiredFast = true;
            } else if (st.fast && distM >= exitR && leaving) {
                desiredFast = false;
            }

            if (desiredFast != st.fast) {
                st.fast = desiredFast;
                int hz = desiredFast ? 5 : 1;
                log.info("module sampling {} -> {}Hz (dist={}m r={}m speed={}km/h)",
                        serial, hz, Math.round(distM), Math.round(triggerR), Math.round(speed));
                commandService.setSamplingHz(serial, hz);
            }
        }
    }

    /**
     * Safety sweep: any device still at 5 Hz that is no longer in the finish
     * zone gets forced back to 1 Hz. Covers the cases the event-driven
     * {@link #decide} path can miss — the rider stopped right after crossing
     * (no more fixes to trigger the "leaving" transition), went offline, or
     * the ride ended. Prevents a module from being stranded at 5 Hz.
     */
    @Scheduled(fixedDelay = 5_000L)
    public void watchdog() {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, DeviceState> e : states.entrySet()) {
            String serial = e.getKey();
            DeviceState st = e.getValue();
            synchronized (st) {
                if (!st.fast) continue;

                boolean revert = false;
                String reason = null;
                if (now - st.lastFixAtMs > FAST_STALE_TIMEOUT_MS) {
                    revert = true;
                    reason = "stale(" + (now - st.lastFixAtMs) + "ms)";
                } else if (st.lastDistM != null && st.lastDistM >= WATCHDOG_EXIT_RADIUS_M) {
                    revert = true;
                    reason = "left-zone(" + Math.round(st.lastDistM) + "m)";
                } else if (st.rideId != null) {
                    RideRecord ride = rideRepository.findById(st.rideId).orElse(null);
                    if (ride == null || !"active".equals(ride.getStatus())) {
                        revert = true;
                        reason = "ride-inactive";
                    }
                }

                if (revert) {
                    st.fast = false;
                    st.lastDistM = null;
                    log.info("module sampling watchdog: {} -> 1Hz ({})", serial, reason);
                    commandService.setSamplingHz(serial, 1);
                }
            }
        }
    }

    private static final class DeviceState {
        boolean fast = false;
        Double lastDistM = null;
        Long rideId = null;
        long lastFixAtMs = 0L;
    }
}
