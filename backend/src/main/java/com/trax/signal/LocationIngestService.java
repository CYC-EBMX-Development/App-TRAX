package com.trax.signal;

import com.trax.model.Bicycle;
import com.trax.model.RidePoint;
import com.trax.model.RideRecord;
import com.trax.repository.BicycleRepository;
import com.trax.repository.RidePointRepository;
import com.trax.repository.RideRecordRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;

/**
 * Single business-layer entry point for all location data, regardless of
 * whether it came from a TRAX module (MQTT realtime, MQTT-backfill,
 * BLE-relay) or the phone GPS (HTTP batch).
 *
 * <p>Responsibilities:
 * <ul>
 *   <li>Validate timestamp sanity (reject future-skewed and stale frames).</li>
 *   <li>Resolve which {@link RideRecord} a frame belongs to by
 *       {@code (bike, capturedAtMs)} time window — works for both live
 *       data and delayed BLE/MQTT-backfill.</li>
 *   <li>Insert {@link RidePoint} rows that downstream code (lap detection,
 *       stats, race replay) reads. Dedup on {@code (rideId, capturedAtMs)}.</li>
 *   <li>Expose {@link #isLive(UnifiedLocationFrame)} so WebSocket fan-out
 *       can suppress old backfilled frames that would otherwise teleport
 *       live UIs.</li>
 * </ul>
 *
 * <p>This class is the only writer to {@code ride_points} for module data.
 * Phone batches route through {@link #ingestPhone(RideRecord, UnifiedLocationFrame)}
 * so both sources land in the table with consistent shape and metadata.
 */
@Service
public class LocationIngestService {

    private static final Logger log = LoggerFactory.getLogger(LocationIngestService.class);

    /** Frames older than this are still saved but NOT broadcast to live WS subscribers. */
    public static final long WS_BROADCAST_MAX_AGE_MS = 5_000L;
    /** Frames timestamped more than this far in the future are rejected (clock skew). */
    static final long REJECT_FUTURE_MS = 60_000L;
    /** Frames older than this are rejected outright (almost certainly bogus). */
    static final long REJECT_PAST_MS   = 7L * 24 * 3600_000L;

    private final BicycleRepository bicycleRepository;
    private final RideRecordRepository rideRecordRepository;
    private final RidePointRepository ridePointRepository;

    public LocationIngestService(BicycleRepository bicycleRepository,
                                 RideRecordRepository rideRecordRepository,
                                 RidePointRepository ridePointRepository) {
        this.bicycleRepository = bicycleRepository;
        this.rideRecordRepository = rideRecordRepository;
        this.ridePointRepository = ridePointRepository;
    }

    /** True iff the frame is recent enough that broadcasting it on WS won't confuse live UIs. */
    public boolean isLive(UnifiedLocationFrame frame) {
        return frame != null && (System.currentTimeMillis() - frame.capturedAtMs() < WS_BROADCAST_MAX_AGE_MS);
    }

    /**
     * Module path: caller knows the serial only. We resolve the bike, find
     * whichever ride covers the frame's capturedAtMs window (live or
     * historical for backfill), and write a ride_point if not duplicate.
     *
     * @return inserted RidePoint, or empty if no bike / no covering ride / dup / sanity-rejected.
     */
    @Transactional
    public Optional<RidePoint> ingestModule(String serialNo, UnifiedLocationFrame frame) {
        if (serialNo == null || serialNo.isBlank()) return Optional.empty();
        if (!sanityOk(frame, "module:" + serialNo)) return Optional.empty();

        List<Bicycle> bikes = bicycleRepository.findByTraxSerialNumber(serialNo);
        if (bikes.isEmpty()) {
            // Module is online but bound to no bike yet — fine, just no ride to attach to.
            return Optional.empty();
        }
        // Legacy data may have multiple bikes claiming the same serial.
        // We pick the most-recently-bound (last in list); the bicycles-table-level
        // guard at create/update time prevents new dups going forward.
        Bicycle bike = bikes.get(bikes.size() - 1);

        return persistForBike(bike, frame);
    }

    /**
     * Phone path: caller already pre-resolved the ride from the URL
     * (POST /api/rides/{id}/points). We honour the explicit ride but
     * still stamp and dedup uniformly.
     */
    @Transactional
    public Optional<RidePoint> ingestPhone(RideRecord ride, UnifiedLocationFrame frame) {
        if (ride == null) return Optional.empty();
        if (!sanityOk(frame, "phone:ride=" + ride.getId())) return Optional.empty();
        return persistForRide(ride, frame);
    }

    // ── internals ─────────────────────────────────────────────────────────

    private Optional<RidePoint> persistForBike(Bicycle bike, UnifiedLocationFrame frame) {
        LocalDateTime capturedDt = LocalDateTime.ofInstant(
                Instant.ofEpochMilli(frame.capturedAtMs()), ZoneId.systemDefault());

        List<RideRecord> rides = rideRecordRepository
                .findRideCoveringTime(bike.getId(), capturedDt);
        if (rides.isEmpty()) {
            // Bike has no ride open at this captured moment — module is just
            // sitting idle. Telemetry table still gets the row (handled by
            // ModuleTelemetryService); we just don't have a ride to attach to.
            return Optional.empty();
        }
        return persistForRide(rides.get(0), frame);
    }

    private Optional<RidePoint> persistForRide(RideRecord ride, UnifiedLocationFrame frame) {
        if (ridePointRepository.existsByRideIdAndCapturedAtMs(ride.getId(), frame.capturedAtMs())) {
            return Optional.empty();
        }

        RidePoint p = new RidePoint();
        p.setRide(ride);
        p.setLatitude(frame.latitude());
        p.setLongitude(frame.longitude());
        p.setSpeed(frame.speedMps() != null ? frame.speedMps() : 0.0);
        p.setAltitude(frame.altitude() != null ? frame.altitude() : 0.0);
        p.setTimestamp(LocalDateTime.ofInstant(
                Instant.ofEpochMilli(frame.capturedAtMs()), ZoneId.systemDefault()));
        p.setCapturedAtMs(frame.capturedAtMs());
        p.setSource(frame.source().name().toLowerCase());

        try {
            return Optional.of(ridePointRepository.save(p));
        } catch (DataIntegrityViolationException dup) {
            // Lost a race against a concurrent ingest path — treat as dedup hit.
            return Optional.empty();
        }
    }

    private boolean sanityOk(UnifiedLocationFrame frame, String label) {
        if (frame == null) return false;
        if (!coordsValid(frame.latitude(), frame.longitude())) {
            // Module with no GNSS fix emits the sentinel (lat=90, lon=0).
            // Such "no fix" frames must never reach ride_points — they
            // teleport replay polylines to the North Pole and inflate distance.
            log.debug("ingest rejected: invalid coords {} lat={} lon={}",
                    label, frame.latitude(), frame.longitude());
            return false;
        }
        long age = System.currentTimeMillis() - frame.capturedAtMs();
        if (age < -REJECT_FUTURE_MS) {
            log.warn("ingest rejected: future timestamp source={} sourceId={} ageMs={}",
                    frame.source(), frame.sourceId(), age);
            return false;
        }
        if (age > REJECT_PAST_MS) {
            log.warn("ingest rejected: too old source={} sourceId={} ageDays={}",
                    frame.source(), frame.sourceId(), age / (24L * 3600_000L));
            return false;
        }
        return true;
    }

    /**
     * Rejects "no GNSS fix" sentinels and out-of-range coordinates.
     * Module firmware emits (lat=90, lon=0) when it has no fix; (0,0) is the
     * classic null-island bug. Either would corrupt the recorded track.
     */
    public static boolean coordsValid(double lat, double lon) {
        if (Double.isNaN(lat) || Double.isNaN(lon)) return false;
        if (lat >= 90.0 || lat <= -90.0) return false;          // 90 = module no-fix sentinel
        if (lon < -180.0 || lon > 180.0) return false;
        if (lat == 0.0 && lon == 0.0) return false;             // null island
        return true;
    }
}
