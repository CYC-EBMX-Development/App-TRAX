package com.trax.signal;

import com.cyc.iot.common.model.CtrlFrame;
import com.trax.model.Bicycle;
import com.trax.model.RideCtrlPoint;
import com.trax.model.RideRecord;
import com.trax.repository.BicycleRepository;
import com.trax.repository.RideCtrlPointRepository;
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
import java.util.concurrent.ConcurrentHashMap;

/**
 * Persists controller telemetry ({@link CtrlFrame}) into TRAX's own
 * {@code ride_ctrl_points} table — the ctrl analog of
 * {@link LocationIngestService} for GPS points. Fully decoupled from
 * vesc-iot / iot-api: data is sourced from the shared MQTT broker and stored
 * locally, so the analysis page reads only TRAX's DB.
 *
 * <p><b>Lifecycle</b>: a frame is attached to whichever ride covers its
 * timestamp ({@code start_time ≤ ts ≤ end_time}); when no ride is active the
 * frame is dropped. So recording starts at ride start and stops at ride end,
 * with no explicit on/off switch — identical to the GPS ride_points path.
 *
 * <p><b>Throttle (方案B)</b>: the module emits ctrl at a fixed firmware rate
 * (~5 Hz), but we only KEEP rows at the GPS sampling cadence for the device —
 * 1 Hz baseline, 5 Hz near the finish line — by consulting
 * {@link ModuleSamplingCoordinator#isFast(String)}. This keeps stored volume
 * aligned with GPS (~1800 rows / 30 min ride) and requires no firmware change.
 */
@Service
public class CtrlIngestService {

    private static final Logger log = LoggerFactory.getLogger(CtrlIngestService.class);

    /** Keep-interval in the two sampling modes. */
    private static final long BASE_INTERVAL_MS = 1_000L; // 1 Hz
    private static final long FAST_INTERVAL_MS = 200L;    // 5 Hz
    /** Allow a frame slightly early so jitter doesn't drop every other 1 Hz row. */
    private static final long INTERVAL_TOLERANCE_MS = 50L;

    /** Reject frames timestamped this far in the future (clock skew) / past (bogus). */
    private static final long REJECT_FUTURE_MS = 60_000L;
    private static final long REJECT_PAST_MS   = 7L * 24 * 3600_000L;

    private final BicycleRepository bicycleRepository;
    private final RideRecordRepository rideRecordRepository;
    private final RideCtrlPointRepository ctrlPointRepository;
    private final ModuleSamplingCoordinator samplingCoordinator;

    /** Last kept-frame epoch ms per serial, for cadence throttling. */
    private final ConcurrentHashMap<String, Long> lastKeptMs = new ConcurrentHashMap<>();

    public CtrlIngestService(BicycleRepository bicycleRepository,
                             RideRecordRepository rideRecordRepository,
                             RideCtrlPointRepository ctrlPointRepository,
                             ModuleSamplingCoordinator samplingCoordinator) {
        this.bicycleRepository = bicycleRepository;
        this.rideRecordRepository = rideRecordRepository;
        this.ctrlPointRepository = ctrlPointRepository;
        this.samplingCoordinator = samplingCoordinator;
    }

    /**
     * Resolve the bike + covering ride for a module ctrl frame and persist it
     * if it passes the cadence throttle and is not a duplicate.
     *
     * @return inserted row, or empty if no bike / no active ride / throttled / dup.
     */
    @Transactional
    public Optional<RideCtrlPoint> ingestModule(String serialNo, CtrlFrame frame) {
        if (serialNo == null || serialNo.isBlank() || frame == null || frame.getTs() == null) {
            return Optional.empty();
        }
        long capturedAtMs = frame.getTs().toEpochMilli();
        long age = System.currentTimeMillis() - capturedAtMs;
        if (age < -REJECT_FUTURE_MS || age > REJECT_PAST_MS) {
            log.debug("ctrl rejected: timestamp out of range serial={} ageMs={}", serialNo, age);
            return Optional.empty();
        }

        List<Bicycle> bikes = bicycleRepository.findByTraxSerialNumber(serialNo);
        if (bikes.isEmpty()) return Optional.empty();
        Bicycle bike = bikes.get(bikes.size() - 1);

        LocalDateTime capturedDt = LocalDateTime.ofInstant(
                Instant.ofEpochMilli(capturedAtMs), ZoneId.systemDefault());
        List<RideRecord> rides = rideRecordRepository.findRideCoveringTime(bike.getId(), capturedDt);
        if (rides.isEmpty()) return Optional.empty();   // no active ride → don't record

        // Cadence throttle keyed to the device's current GPS sampling mode.
        long interval = samplingCoordinator.isFast(serialNo) ? FAST_INTERVAL_MS : BASE_INTERVAL_MS;
        Long last = lastKeptMs.get(serialNo);
        if (last != null && capturedAtMs - last < interval - INTERVAL_TOLERANCE_MS) {
            return Optional.empty();                    // too soon since last kept frame
        }

        RideRecord ride = rides.get(0);
        if (ctrlPointRepository.existsByRideIdAndCapturedAtMs(ride.getId(), capturedAtMs)) {
            return Optional.empty();
        }

        RideCtrlPoint p = new RideCtrlPoint();
        p.setRide(ride);
        p.setCapturedAtMs(capturedAtMs);
        p.setTimestamp(capturedDt);
        p.setTempFet(frame.getTempFet());
        p.setTempMotor(frame.getTempMotor());
        p.setCurrentMotor(frame.getCurrentMotor());
        p.setCurrentInput(frame.getCurrentInput());
        p.setIdAxis(frame.getId());
        p.setIqAxis(frame.getIq());
        p.setDuty(frame.getDuty());
        p.setVin(frame.getVin());
        p.setThrottle(frame.getThrottle());
        p.setRegen(frame.getRegen());
        p.setVd(frame.getVd());
        p.setVq(frame.getVq());

        try {
            RideCtrlPoint saved = ctrlPointRepository.save(p);
            lastKeptMs.put(serialNo, capturedAtMs);
            return Optional.of(saved);
        } catch (DataIntegrityViolationException dup) {
            return Optional.empty();
        }
    }
}
