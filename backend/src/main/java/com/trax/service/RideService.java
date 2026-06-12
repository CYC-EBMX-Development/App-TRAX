package com.trax.service;

import com.trax.dto.*;
import com.trax.model.*;
import com.trax.repository.*;
import com.trax.signal.LocationIngestService;
import com.trax.signal.PhoneGpsAdapter;
import com.trax.signal.UnifiedLocationFrame;
import com.trax.websocket.RideLapWebSocketHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import com.trax.util.GeoUtils;

@Service
public class RideService {
    private static final Logger log = LoggerFactory.getLogger(RideService.class);

    private final RideRecordRepository rideRecordRepository;
    private final RidePointRepository ridePointRepository;
    private final BicycleRepository bicycleRepository;
    private final HistoryRideRecordRepository historyRideRecordRepository;
    private final HistoryRidePointRepository historyRidePointRepository;
    private final RideLapRepository rideLapRepository;
    private final TrailRepository trailRepository;
    private final TrailPointRepository trailPointRepository;
    private final RaceParticipantRepository raceParticipantRepository;
    private final RaceRepository raceRepository;
    private final UserCheckpointRepository userCheckpointRepository;
    private final RideLapCheckpointRepository rideLapCheckpointRepository;
    private final LocationIngestService locationIngestService;

    /** Optional — only present when the WebSocket auto-config is active. */
    @Autowired(required = false)
    private RideLapWebSocketHandler lapWsHandler;

    // Lap detection thresholds
    private static final double OVERLAP_THRESHOLD_KM = 0.03; // 30m to count as "on trail"
    private static final double LAP_MIN_EXCURSION_KM = 0.05;     // 50m away before lap can close
    private static final long LAP_MIN_DURATION_SEC = 15;         // ignore noisy lap closures < 15s
    /** Radius (km) around a checkpoint within which a ride point counts as
     *  passing through that checkpoint. */
    private static final double CHECKPOINT_PASS_KM = 0.025; // 25 m
    /** Half-width (km) of the virtual finish line. The line is a segment
     *  centred on the trail start point and perpendicular to the trail's
     *  initial heading; a lap closes when the rider's GPS segment crosses
     *  this line in the trail's forward direction. */
    private static final double LAP_FINISH_LINE_HALF_WIDTH_KM = 0.020; // ±20 m
    /** Minimum distance (m) between the start point and the trail point
     *  used to derive the trail's initial heading. Larger values average
     *  out GPS noise in the first few recorded trail points (Record mode)
     *  while still picking up the user's 2nd pick-point in Pick Point mode. */
    private static final double HEADING_REF_MIN_METERS = 20.0;
    /** Approach-direction filter: how many recent ride points to look back
     *  over when judging whether the rider is approaching the finish line
     *  along the trail's forward direction (not just randomly crossing it
     *  while moving around in the pit area). */
    private static final int APPROACH_LOOKBACK_POINTS = 5;
    /** Approach-direction filter: max recent ride points retained for the
     *  distance-based leaving window. Large enough to span the configured
     *  net-displacement threshold even at 5 Hz dense sampling at low speed
     *  (64 pts ≈ 12.8 s @5 Hz / 64 s @1 Hz). */
    private static final int APPROACH_BUFFER_POINTS = 64;
    /** Approach-direction filter: minimum cosine between the rider's recent
     *  net displacement vector and the trail's heading vector. 0.5 ≈ 60°
     *  cone around the forward direction. */
    private static final double APPROACH_COS_THRESHOLD = 0.5;

    /**
     * Minimum net displacement (m) the rider must move AWAY from the finish
     * line — measured over a distance-based window, NOT a fixed point count
     * — before a finish-line crossing is accepted. Confirms the rider is
     * genuinely leaving (lap complete) rather than hovering/jittering near
     * the line. Distance-based so it is independent of sampling rate (the
     * 5 Hz finish-line densification used to shrink the old fixed 5-point
     * window below threshold and silently drop laps).
     *
     * <p>Configurable via {@code trax.lap.leaving-net-displacement-m}
     * (default 8.0). 8 m suits a dual-band L1+L5 antenna (~1–2 m CEP);
     * raise toward ~20 m for a noisier single-band L1 module.
     */
    @org.springframework.beans.factory.annotation.Value("${trax.lap.leaving-net-displacement-m:8.0}")
    private double lapLeavingNetDisplacementM;

    public RideService(RideRecordRepository rideRecordRepository,
                       RidePointRepository ridePointRepository,
                       BicycleRepository bicycleRepository,
                       HistoryRideRecordRepository historyRideRecordRepository,
                       HistoryRidePointRepository historyRidePointRepository,
                       RideLapRepository rideLapRepository,
                       TrailRepository trailRepository,
                       TrailPointRepository trailPointRepository,
                       RaceParticipantRepository raceParticipantRepository,
                       RaceRepository raceRepository,
                       UserCheckpointRepository userCheckpointRepository,
                       RideLapCheckpointRepository rideLapCheckpointRepository,
                       LocationIngestService locationIngestService) {
        this.rideRecordRepository = rideRecordRepository;
        this.ridePointRepository = ridePointRepository;
        this.bicycleRepository = bicycleRepository;
        this.historyRideRecordRepository = historyRideRecordRepository;
        this.historyRidePointRepository = historyRidePointRepository;
        this.rideLapRepository = rideLapRepository;
        this.trailRepository = trailRepository;
        this.trailPointRepository = trailPointRepository;
        this.raceParticipantRepository = raceParticipantRepository;
        this.raceRepository = raceRepository;
        this.userCheckpointRepository = userCheckpointRepository;
        this.rideLapCheckpointRepository = rideLapCheckpointRepository;
        this.locationIngestService = locationIngestService;
    }

    public List<RideRecord> getUserRides(Long userId) {
        return rideRecordRepository.findByUserIdOrderByStartTimeDesc(userId)
                .stream()
                .filter(r -> !r.isHiddenByOwner())
                .toList();
    }

    public RideRecordDto getActiveRide(Long userId) {
        return rideRecordRepository
                .findFirstByUserIdAndStatusInOrderByStartTimeDesc(userId, List.of("active", "paused"))
                .map(this::toRideRecordDto)
                .orElse(null);
    }

    public RideRecordDto toRideRecordDto(RideRecord ride) {
        RideRecordDto dto = RideRecordDto.fromEntity(ride);
        if (ride != null && ride.getId() != null) {
            List<RaceParticipant> links = raceParticipantRepository.findByRideId(ride.getId());
            if (!links.isEmpty() && links.get(0).getRace() != null) {
                dto.setRaceId(links.get(0).getRace().getId());
                dto.setGameType(links.get(0).getRace().getGameType());
            }
        }
        return dto;
    }

    public RideRecord getRideById(Long id) {
        return rideRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Ride record not found"));
    }

    // ── Ride Lifecycle ──────────────────────────────────────

    public RideRecordDto startRide(Long userId, RideStartRequest request) {
        Bicycle bicycle = bicycleRepository.findById(request.getBicycleId())
                .orElseThrow(() -> new IllegalArgumentException("Bicycle not found"));
        if (!bicycle.getOwner().getId().equals(userId)) {
            throw new IllegalArgumentException("Not your bicycle");
        }

        RideRecord ride = new RideRecord();
        ride.setUser(bicycle.getOwner());
        ride.setBicycle(bicycle);
        ride.setStartTime(LocalDateTime.now());
        ride.setStatus("active");
        ride.setMode(request.getMode());
        ride.setTotalPausedSeconds(0.0);
        ride.setDistance(0.0);
        ride.setAvgSpeed(0.0);
        ride.setMaxSpeed(0.0);
        ride.setElevation(0.0);

        // Lap Timer setup
        if (request.getTrailId() != null) {
            Trail trail = trailRepository.findById(request.getTrailId())
                    .orElseThrow(() -> new IllegalArgumentException("Trail not found"));
            ride.setTrail(trail);
            if (request.getTargetLaps() != null && request.getTargetLaps() > 0) {
                ride.setTargetLaps(request.getTargetLaps());
                ride.setCompletedLaps(0);
            }
            ride.setSource("lap_timer");
        } else {
            ride.setSource("free_ride");
        }

        return toRideRecordDto(rideRecordRepository.save(ride));
    }

    public RideRecordDto pauseRide(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);
        if (!"active".equals(ride.getStatus())) {
            throw new IllegalStateException("Ride is not active");
        }
        ride.setStatus("paused");
        ride.setLastPausedAt(LocalDateTime.now());
        return toRideRecordDto(rideRecordRepository.save(ride));
    }

    public RideRecordDto resumeRide(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);
        if (!"paused".equals(ride.getStatus())) {
            throw new IllegalStateException("Ride is not paused");
        }
        if (ride.getLastPausedAt() != null) {
            double pauseSec = Duration.between(ride.getLastPausedAt(), LocalDateTime.now()).toMillis() / 1000.0;
            ride.setTotalPausedSeconds((ride.getTotalPausedSeconds() != null ? ride.getTotalPausedSeconds() : 0) + pauseSec);
        }
        ride.setStatus("active");
        ride.setLastPausedAt(null);
        return toRideRecordDto(rideRecordRepository.save(ride));
    }

    public RideRecordDto stopRide(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);
        if ("completed".equals(ride.getStatus())) {
            throw new IllegalStateException("Ride already completed");
        }
        // Accumulate remaining pause time if stopped while paused
        if ("paused".equals(ride.getStatus()) && ride.getLastPausedAt() != null) {
            double pauseSec = Duration.between(ride.getLastPausedAt(), LocalDateTime.now()).toMillis() / 1000.0;
            ride.setTotalPausedSeconds((ride.getTotalPausedSeconds() != null ? ride.getTotalPausedSeconds() : 0) + pauseSec);
        }
        ride.setEndTime(LocalDateTime.now());
        ride.setStatus("completed");
        ride.setLastPausedAt(null);
        calculateFinalStats(ride);
        return toRideRecordDto(rideRecordRepository.save(ride));
    }

    // ── Points & Stats ──────────────────────────────────────

    public RideStatsDto addPointsAndGetStats(Long rideId, Long userId, RidePointBatchRequest request) {
        RideRecord ride = getOwnedRide(rideId, userId);
        if (request.getPoints() != null) {
            for (RidePointDto dto : request.getPoints()) {
                // Route phone batch through the unified ingest path so both
                // module and phone data land in ride_points with consistent
                // shape (captured_at_ms, source) and dedup. Business code
                // downstream is source-agnostic.
                UnifiedLocationFrame frame = PhoneGpsAdapter.fromDto(dto, null);
                if (frame != null) {
                    locationIngestService.ingestPhone(ride, frame);
                }
            }
        }
        return computeCurrentStats(ride);
    }

    public RideStatsDto getStats(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);
        return computeCurrentStats(ride);
    }

    public List<RidePointDto> getPoints(Long rideId, Long userId) {
        getOwnedRide(rideId, userId); // ownership check
        return ridePointRepository.findByRideIdOrderByTimestampAsc(rideId).stream()
                .map(p -> {
                    RidePointDto dto = new RidePointDto();
                    dto.setLatitude(p.getLatitude());
                    dto.setLongitude(p.getLongitude());
                    dto.setSpeed(p.getSpeed());
                    dto.setAltitude(p.getAltitude());
                    dto.setTimestamp(p.getTimestamp().toString());
                    return dto;
                }).toList();
    }

    // ── Delete (archive to history) ───────────────────────────

    @Transactional
    public void deleteRide(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);

        // If this ride is part of a race, perform a soft-delete: hide it from
        // the owner’s personal history but keep all points/laps and the race
        // participant link intact, so other riders can still see this rider’s
        // path on the race detail / replay views.
        List<RaceParticipant> linkedParticipants = raceParticipantRepository.findByRideId(rideId);
        if (!linkedParticipants.isEmpty()) {
            ride.setHiddenByOwner(true);
            rideRecordRepository.save(ride);
            return;
        }

        // Archive ride record (historyBicycleId is null since bike is not being archived)
        HistoryRideRecord historyRide = historyRideRecordRepository.save(
                HistoryRideRecord.fromRideRecord(ride, null));

        // Archive ride points
        List<RidePoint> points = ridePointRepository.findByRideId(rideId);
        List<HistoryRidePoint> historyPoints = points.stream()
                .map(p -> HistoryRidePoint.fromRidePoint(p, historyRide.getId()))
                .toList();
        historyRidePointRepository.saveAll(historyPoints);

        // Delete originals
        ridePointRepository.deleteByRideId(rideId);
        rideLapRepository.deleteByRideId(rideId);
        rideRecordRepository.delete(ride);
    }

    public List<RideLapDto> getLaps(Long rideId, Long userId) {
        RideRecord ride = getOwnedRide(rideId, userId);

        // Re-run lap detection on demand. The algorithm is idempotent
        // (it only emits laps after the last persisted one) so this is
        // safe to invoke on every read. It also allows historical rides
        // to benefit when the detection algorithm is upgraded.
        if (ride.getTrail() != null && ride.getTargetLaps() != null) {
            List<RidePoint> points = ridePointRepository
                    .findByRideIdOrderByTimestampAsc(rideId);
            if (!points.isEmpty()) {
                detectAndPersistLaps(ride, points);
            }
        }

        List<RideLap> laps = rideLapRepository.findByRideIdOrderByLapNumberAsc(rideId);

        // Calculate/recalculate overlapPercent for all laps with a trail
        boolean needsSave = false;
        if (ride.getTrail() != null && !laps.isEmpty()) {
            List<TrailPoint> trailPoints = trailPointRepository
                    .findByTrailIdOrderBySequenceIndexAsc(ride.getTrail().getId());
            List<RidePoint> ridePoints = ridePointRepository.findByRideIdOrderByTimestampAsc(rideId);
            if (trailPoints.size() >= 2 && !ridePoints.isEmpty()) {
                for (RideLap lap : laps) {
                    List<RidePoint> lapPts = ridePoints.stream()
                            .filter(p -> p.getTimestamp() != null
                                    && !p.getTimestamp().isBefore(lap.getStartTime())
                                    && !p.getTimestamp().isAfter(lap.getEndTime()))
                            .toList();
                    double newOverlap = calculateOverlap(lapPts, trailPoints);
                    if (lap.getOverlapPercent() == null || Math.abs(lap.getOverlapPercent() - newOverlap) > 0.1) {
                        lap.setOverlapPercent(newOverlap);
                        needsSave = true;
                    }
                }
            }
        }
        if (needsSave) rideLapRepository.saveAll(laps);

        return mapLapsWithPasses(laps);
    }

    /** Map a list of {@link RideLap}s to DTOs with their checkpoint passes
     *  attached via a single batch query. */
    public List<RideLapDto> mapLapsWithPasses(List<RideLap> laps) {
        if (laps.isEmpty()) return List.of();
        List<Long> lapIds = laps.stream().map(RideLap::getId).toList();
        java.util.Map<Long, java.util.List<RideLapCheckpoint>> byLap = new java.util.HashMap<>();
        for (RideLapCheckpoint cp : rideLapCheckpointRepository
                .findByLapIdInOrderByLapIdAscSequenceIndexAsc(lapIds)) {
            byLap.computeIfAbsent(cp.getLapId(), k -> new java.util.ArrayList<>()).add(cp);
        }
        return laps.stream()
                .map(l -> RideLapDto.fromEntity(l, byLap.getOrDefault(l.getId(), List.of())))
                .toList();
    }

    // ── Private Helpers ─────────────────────────────────────

    private RideRecord getOwnedRide(Long rideId, Long userId) {
        RideRecord ride = rideRecordRepository.findById(rideId)
                .orElseThrow(() -> new IllegalArgumentException("Ride not found"));
        if (!ride.getUser().getId().equals(userId)) {
            throw new IllegalArgumentException("Not your ride");
        }
        return ride;
    }

    /** Compute live stats for a race participant's ride (no ownership check). */
    public RideStatsDto computeRaceStats(RideRecord ride) {
        return computeCurrentStats(ride);
    }

    private RideStatsDto computeCurrentStats(RideRecord ride) {
        List<RidePoint> points = ridePointRepository.findByRideIdOrderByTimestampAsc(ride.getId());

        double totalDistKm = 0;
        double maxSpeed = 0;
        double totalElevGain = 0;

        for (int i = 1; i < points.size(); i++) {
            RidePoint prev = points.get(i - 1);
            RidePoint curr = points.get(i);
            totalDistKm += GeoUtils.haversineKm(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
            if (curr.getSpeed() > maxSpeed) maxSpeed = curr.getSpeed();
            double altDiff = curr.getAltitude() - prev.getAltitude();
            if (altDiff > 0) totalElevGain += altDiff;
        }

        // Duration = elapsed - paused
        LocalDateTime end = ride.getEndTime() != null ? ride.getEndTime() : LocalDateTime.now();
        long totalSec = Duration.between(ride.getStartTime(), end).toSeconds();
        double paused = ride.getTotalPausedSeconds() != null ? ride.getTotalPausedSeconds() : 0;
        // If currently paused, add ongoing pause
        if ("paused".equals(ride.getStatus()) && ride.getLastPausedAt() != null) {
            paused += Duration.between(ride.getLastPausedAt(), LocalDateTime.now()).toSeconds();
        }
        long rideSec = Math.max(0, totalSec - (long) paused);

        double avgSpeed = rideSec > 0 ? (totalDistKm / (rideSec / 3600.0)) : 0;

        RideStatsDto stats = new RideStatsDto();
        stats.setRideId(ride.getId());
        stats.setStatus(ride.getStatus());
        stats.setDurationSeconds(rideSec);
        stats.setDistanceKm(Math.round(totalDistKm * 100.0) / 100.0);
        stats.setAvgSpeedKmh(Math.round(avgSpeed * 10.0) / 10.0);
        stats.setMaxSpeedKmh(Math.round(maxSpeed * 10.0) / 10.0);
        stats.setElevationMeters(Math.round(totalElevGain * 10.0) / 10.0);
        if (!points.isEmpty()) {
            RidePoint last = points.get(points.size() - 1);
            stats.setCurrentLatitude(last.getLatitude());
            stats.setCurrentLongitude(last.getLongitude());
        }

        // Lap Timer: detect new laps and include in stats
        if (ride.getTrail() != null && ride.getTargetLaps() != null) {
            detectAndPersistLaps(ride, points);
            List<RideLap> laps = rideLapRepository.findByRideIdOrderByLapNumberAsc(ride.getId());
            stats.setLaps(mapLapsWithPasses(laps));
            stats.setTargetLaps(ride.getTargetLaps());
            stats.setCompletedLaps(ride.getCompletedLaps() != null ? ride.getCompletedLaps() : 0);
        }
        return stats;
    }

    /**
     * Lap detection algorithm (finish-line crossing):
     *  1. Build a virtual finish line: a short segment centred on the
     *     trail start point and perpendicular to the trail's initial
     *     heading (derived from the first trail point at least
     *     {@link #HEADING_REF_MIN_METERS} away). Half-width =
     *     {@link #LAP_FINISH_LINE_HALF_WIDTH_KM}.
     *  2. Walk the rider's GPS samples in order. For every consecutive
     *     pair (prev → curr) test whether the segment crosses the finish
     *     line. Direction filter: the rider's velocity vector must have a
     *     positive component along the trail heading (forward crossings
     *     only) so going backward across the line never counts.
     *  3. Approach-direction filter: even when a forward crossing is
     *     detected geometrically, only accept it if the rider's net
     *     displacement over a distance-based leaving window (at least
     *     {@code trax.lap.leaving-net-displacement-m} metres, sampling-rate
     *     independent) is directionally within ±60° of the trail heading.
     *     This suppresses false positives from the rider milling around in
     *     a pit/parking area near the finish line.
     *  4. The exact crossing timestamp is interpolated linearly between
     *     prev.ts and curr.ts using the intersection parameter t.
     *  5. First accepted crossing arms the gate — lap 1 starts at that
     *     timestamp (no standing-at-start padding). Subsequent accepted
     *     crossings close the in-progress lap.
     *  6. Anti-jitter: a lap is only closed when the rider has travelled
     *     at least {@link #LAP_MIN_EXCURSION_KM} from the start AND the
     *     in-progress lap is at least {@link #LAP_MIN_DURATION_SEC} long.
     *
     * Idempotent: only persists laps beyond the existing count and auto-
     * completes the ride when target lap count is reached.
     */
    private void detectAndPersistLaps(RideRecord ride, List<RidePoint> points) {
        Trail trail = ride.getTrail();
        if (trail == null || trail.getStartLatitude() == null || trail.getStartLongitude() == null) return;
        if (points.isEmpty()) return;
        // NOTE: previously skipped completed rides here. Removed so that the
        // algorithm can backfill laps for historical rides (idempotent: only
        // processes points after the last persisted lap; auto-complete guard
        // below already checks status to avoid re-triggering finish logic).
        //
        // …with one exception: lap-timer rides that have already met their
        // target lap count are frozen. Without this guard, a stale or
        // continued point stream (e.g. simulator still emitting after the
        // ride auto-completed, or a phone that uploads buffered points after
        // the user already finished) keeps closing more laps past the goal
        // — see ride #14 (target=1, completed=21) for the production
        // reproduction. Backfill of incomplete lap-timer rides
        // (existingLapCount < targetLaps) and free rides (targetLaps == 0)
        // is still allowed.
        int existingLapCount = (ride.getCompletedLaps() != null) ? ride.getCompletedLaps() : 0;
        int targetLaps = ride.getTargetLaps() != null ? ride.getTargetLaps() : 0;
        if ("completed".equals(ride.getStatus())
                && targetLaps > 0
                && existingLapCount >= targetLaps) {
            return;
        }

        double startLat = trail.getStartLatitude();
        double startLng = trail.getStartLongitude();

        // Load trail points once for overlap calculation + heading derivation.
        List<TrailPoint> trailPoints = trailPointRepository
                .findByTrailIdOrderBySequenceIndexAsc(trail.getId());

        // Local equirectangular projection (metres) anchored at the start.
        final double R = 6371000.0;
        final double cosLat0 = Math.cos(Math.toRadians(startLat));

        // Derive trail heading unit vector: first trail point
        // >= HEADING_REF_MIN_METERS away from the start. Defaults to north.
        double hX = 0, hY = 1;
        for (TrailPoint tp : trailPoints) {
            double dy = Math.toRadians(tp.getLatitude() - startLat) * R;
            double dx = Math.toRadians(tp.getLongitude() - startLng) * R * cosLat0;
            double mag = Math.hypot(dx, dy);
            if (mag >= HEADING_REF_MIN_METERS) {
                hX = dx / mag;
                hY = dy / mag;
                break;
            }
        }
        // Perpendicular (left-hand normal) and finish-line endpoints (metres).
        final double perpX = -hY;
        final double perpY = hX;
        final double halfW = LAP_FINISH_LINE_HALF_WIDTH_KM * 1000.0;
        final double aX = perpX * halfW, aY = perpY * halfW;
        final double bX = -aX,           bY = -aY;

        // Start of the lap currently in progress: end of last persisted lap
        // (if any). When no lap exists yet, currentLapStart is left null and
        // is established when the very first crossing is detected.
        List<RideLap> existing = rideLapRepository.findByRideIdOrderByLapNumberAsc(ride.getId());
        LocalDateTime currentLapStart = existing.isEmpty()
                ? null
                : existing.get(existing.size() - 1).getEndTime();
        boolean gateArmed = !existing.isEmpty();

        double maxAwayKm = 0;
        double cumulativeKm = 0;
        RidePoint prev = null;
        double[] prevLocal = null;
        List<RideLap> newLaps = new ArrayList<>();
        // For each new lap, the in-order list of (sequenceIndex, passTime, lat, lng)
        // pass tuples captured during that lap. Materialized to RideLapCheckpoint
        // entities after the laps are persisted (need lap.id).
        List<List<Object[]>> newLapPasses = new ArrayList<>();
        List<RidePoint> currentLapPoints = new ArrayList<>();
        // Rolling buffer of the rider's most recent points (regardless of gate
        // state) used by the approach-direction filter.
        java.util.ArrayDeque<RidePoint> recent =
                new java.util.ArrayDeque<>(APPROACH_BUFFER_POINTS + 1);

        // Pre-load this rider's checkpoints for this trail (personal-only).
        Long userId = (ride.getUser() != null) ? ride.getUser().getId() : null;
        List<UserCheckpoint> checkpoints = (userId != null)
                ? userCheckpointRepository
                        .findByUserIdAndTrailIdOrderBySequenceIndexAsc(userId, trail.getId())
                : List.of();

        for (RidePoint p : points) {
            // Skip points before the current lap began (already processed in
            // a previous run for already-persisted laps).
            if (p.getTimestamp() == null
                    || (currentLapStart != null && !p.getTimestamp().isAfter(currentLapStart))) {
                prev = p;
                if (p.getTimestamp() != null) {
                    prevLocal = new double[]{
                            Math.toRadians(p.getLongitude() - startLng) * R * cosLat0,
                            Math.toRadians(p.getLatitude() - startLat) * R
                    };
                    // Keep the approach-direction window primed so that the
                    // first crossing after resume has enough history.
                    recent.addLast(p);
                    while (recent.size() > APPROACH_BUFFER_POINTS) recent.removeFirst();
                }
                continue;
            }

            double curX = Math.toRadians(p.getLongitude() - startLng) * R * cosLat0;
            double curY = Math.toRadians(p.getLatitude() - startLat) * R;
            double distFromStart = GeoUtils.haversineKm(
                    startLat, startLng, p.getLatitude(), p.getLongitude());

            // Always update running totals for the lap-in-progress, but only
            // once the gate has been armed (otherwise we are still waiting
            // for lap 1 to begin).
            if (gateArmed) {
                if (prev != null) {
                    cumulativeKm += GeoUtils.haversineKm(
                            prev.getLatitude(), prev.getLongitude(),
                            p.getLatitude(), p.getLongitude());
                }
                if (distFromStart > maxAwayKm) maxAwayKm = distFromStart;
                currentLapPoints.add(p);
            }

            // Test whether the segment (prev → curr) crosses the finish
            // line in the trail's forward direction.
            if (prev != null && prevLocal != null && prev.getTimestamp() != null) {
                Double tParam = segmentIntersectionParam(
                        prevLocal[0], prevLocal[1], curX, curY,
                        aX, aY, bX, bY);
                if (tParam != null) {
                    double dx = curX - prevLocal[0];
                    double dy = curY - prevLocal[1];
                    boolean forward = (dx * hX + dy * hY) > 0;
                    boolean approachOk = forward && isApproachAligned(
                            recent, p, cosLat0, R, hX, hY, lapLeavingNetDisplacementM);
                    if (forward && approachOk) {
                        long segMs = Duration.between(prev.getTimestamp(), p.getTimestamp()).toMillis();
                        LocalDateTime crossingTs = prev.getTimestamp()
                                .plus(Duration.ofMillis((long) (segMs * tParam)));

                        if (!gateArmed) {
                            // First-ever crossing: arm the gate. Lap 1 begins
                            // at this crossing; no time prior to this counts.
                            gateArmed = true;
                            currentLapStart = crossingTs;
                            maxAwayKm = distFromStart;
                            cumulativeKm = GeoUtils.haversineKm(
                                    prev.getLatitude(), prev.getLongitude(),
                                    p.getLatitude(), p.getLongitude());
                            currentLapPoints.clear();
                            currentLapPoints.add(p);
                        } else {
                            long secInLap = Duration.between(currentLapStart, crossingTs).toSeconds();
                            if (maxAwayKm >= LAP_MIN_EXCURSION_KM
                                    && secInLap >= LAP_MIN_DURATION_SEC) {
                                int lapNumber = existingLapCount + newLaps.size() + 1;
                                RideLap lap = new RideLap();
                                lap.setRideId(ride.getId());
                                lap.setLapNumber(lapNumber);
                                lap.setStartTime(currentLapStart);
                                lap.setEndTime(crossingTs);
                                lap.setDurationSeconds(secInLap);
                                lap.setDistanceKm(Math.round(cumulativeKm * 100.0) / 100.0);
                                lap.setOverlapPercent(calculateOverlap(currentLapPoints, trailPoints));
                                newLaps.add(lap);
                                newLapPasses.add(extractLapPasses(currentLapPoints, checkpoints));

                                // Next lap begins immediately at the crossing.
                                currentLapStart = crossingTs;
                                maxAwayKm = distFromStart;
                                cumulativeKm = GeoUtils.haversineKm(
                                        prev.getLatitude(), prev.getLongitude(),
                                        p.getLatitude(), p.getLongitude());
                                currentLapPoints.clear();
                                currentLapPoints.add(p);
                            }
                        }
                    }
                }
            }

            prev = p;
            prevLocal = new double[]{curX, curY};
            recent.addLast(p);
            while (recent.size() > APPROACH_BUFFER_POINTS) recent.removeFirst();
        }

        if (!newLaps.isEmpty()) {
            rideLapRepository.saveAll(newLaps);
            // Persist checkpoint passes (now that lap.id is assigned).
            persistLapPasses(newLaps, newLapPasses);
            int completed = existingLapCount + newLaps.size();
            ride.setCompletedLaps(completed);

            // Auto-end ride when target reached
            boolean justCompleted = false;
            if (targetLaps > 0 && completed >= targetLaps && !"completed".equals(ride.getStatus())) {
                ride.setEndTime(newLaps.get(newLaps.size() - 1).getEndTime());
                ride.setStatus("completed");
                calculateFinalStats(ride);
                // If this ride belongs to a race, mark the participant finished
                // and complete the race when everyone is done.
                autoFinishRaceParticipantForRide(ride);
                justCompleted = true;
            }
            rideRecordRepository.save(ride);

            // Push every new lap + a final "completed" event to live WS
            // subscribers so the App can refetch /stats without waiting
            // for the next 3 s poll. Best-effort: failures are swallowed.
            broadcastNewLaps(ride, newLaps, completed, targetLaps, justCompleted);
        }
    }

    /**
     * Approach-direction filter (distance-based, sampling-rate independent).
     * Returns true when the rider has moved at least {@code minNetDisplacementM}
     * away from the recent window AND that net displacement is directionally
     * aligned with the trail's forward heading.
     *
     * <p>Walks {@code recent} from newest → oldest and picks the closest-in-time
     * point that is already {@code minNetDisplacementM} away from {@code current},
     * giving the tightest window that still spans the threshold — responsive yet
     * robust to single-point GPS jitter. Crucially the window is defined by
     * DISTANCE, not point count, so 5 Hz finish-line densification can no longer
     * shrink it below threshold (the old fixed 5-point window did, dropping laps).
     *
     * <p>Returns true when history is too short to judge (fewer than
     * {@link #APPROACH_LOOKBACK_POINTS} points — i.e. the rider just started)
     * so the very first crossing can still arm the gate; callers still gate on
     * {@code forward}. Returns false when the rider has enough samples but none
     * spans the threshold (hovering/jittering near the line).
     */
    private static boolean isApproachAligned(
            java.util.Deque<RidePoint> recent, RidePoint current,
            double cosLat0, double R,
            double hX, double hY,
            double minNetDisplacementM) {
        if (recent.size() < APPROACH_LOOKBACK_POINTS) return true;
        double dx = 0, dy = 0, mag = 0;
        boolean reached = false;
        // descendingIterator() = newest → oldest.
        java.util.Iterator<RidePoint> it = recent.descendingIterator();
        while (it.hasNext()) {
            RidePoint r = it.next();
            dx = Math.toRadians(current.getLongitude() - r.getLongitude()) * R * cosLat0;
            dy = Math.toRadians(current.getLatitude() - r.getLatitude()) * R;
            mag = Math.hypot(dx, dy);
            if (mag >= minNetDisplacementM) { reached = true; break; }
        }
        if (!reached) return false; // hovering near the line → don't close a lap
        double cos = (dx * hX + dy * hY) / mag; // (hX,hY) is already unit length
        return cos >= APPROACH_COS_THRESHOLD;
    }

    /**
     * Public entry point used by the module ingest path
     * ({@link com.trax.service.ModuleTelemetryService}) to trigger lap
     * detection immediately after a new module-sourced ride_point is
     * persisted. Without this hook, lap detection for {@code with_module}
     * rides would only run when a client polls {@code /stats} or
     * {@code /laps}, which leaves the auto-finish timer idle whenever the
     * App is backgrounded.
     *
     * <p>No-op (silently returns) when the ride is not a lap-timer ride,
     * is already completed, or has no points yet. Idempotent and safe to
     * call on every frame; the detection algorithm only emits laps beyond
     * the existing count.
     */
    @Transactional
    public void detectLapsForRideId(Long rideId) {
        if (rideId == null) return;
        RideRecord ride = rideRecordRepository.findById(rideId).orElse(null);
        if (ride == null) return;
        if (ride.getTrail() == null || ride.getTargetLaps() == null) return;
        if ("completed".equals(ride.getStatus())) return;
        List<RidePoint> points = ridePointRepository
                .findByRideIdOrderByTimestampAsc(rideId);
        if (points.isEmpty()) return;
        detectAndPersistLaps(ride, points);
    }

    /**
     * Best-effort push of newly persisted laps to live WS subscribers on
     * {@code /ws/rides/{rideId}/laps}. Failures are logged and swallowed
     * so a flaky WebSocket never breaks lap persistence.
     */
    private void broadcastNewLaps(RideRecord ride, List<RideLap> newLaps,
                                  int completed, int targetLaps,
                                  boolean justCompleted) {
        if (lapWsHandler == null) return;
        try {
            String status = ride.getStatus();
            Integer target = ride.getTargetLaps();
            for (RideLap lap : newLaps) {
                String endTs = lap.getEndTime() != null ? lap.getEndTime().toString() : null;
                lapWsHandler.broadcast(ride.getId(), RideLapEventDto.lap(
                        ride.getId(), lap.getLapNumber(), completed, target, status, endTs));
            }
            if (justCompleted) {
                String endTs = ride.getEndTime() != null ? ride.getEndTime().toString() : null;
                lapWsHandler.broadcast(ride.getId(), RideLapEventDto.completed(
                        ride.getId(), completed, target, endTs));
            }
        } catch (Exception e) {
            log.warn("Lap WS broadcast failed ride={}: {}", ride.getId(), e.toString());
        }
    }

    /**
     * Segment–segment intersection in 2D. Returns the parameter t ∈ [0, 1]
     * along segment (p0 → p1) at which it crosses segment (a → b), or null
     * if the segments are parallel or do not intersect.
     */
    private static Double segmentIntersectionParam(
            double p0x, double p0y, double p1x, double p1y,
            double ax,  double ay,  double bx,  double by) {
        double rx = p1x - p0x, ry = p1y - p0y;
        double sx = bx - ax,   sy = by - ay;
        double denom = rx * sy - ry * sx;
        if (Math.abs(denom) < 1e-9) return null;
        double t = ((ax - p0x) * sy - (ay - p0y) * sx) / denom;
        double u = ((ax - p0x) * ry - (ay - p0y) * rx) / denom;
        if (t < 0 || t > 1 || u < 0 || u > 1) return null;
        return t;
    }

    /**
     * When a race ride auto-completes via lap detection, finish the matching
     * participant and check whether all riders have finished so the race can
     * be marked completed without depending on someone polling live data.
     */
    private void autoFinishRaceParticipantForRide(RideRecord ride) {
        try {
            List<RaceParticipant> links = raceParticipantRepository.findByRideId(ride.getId());
            if (links.isEmpty()) return;
            RaceParticipant rp = links.get(0);
            Race race = rp.getRace();
            if (race == null) return;
            if (!"finished".equals(rp.getStatus())) {
                rp.setStatus("finished");
                raceParticipantRepository.save(rp);
            }
            // Rank by REAL finish time (crossing instant of the target lap),
            // not by detection order — uploads can arrive out of order, so
            // the rider whose finish point reaches the server first is not
            // necessarily the one who crossed the line first.
            recomputeFinishRanksByTime(race.getId());
            // Re-load and check whether all riders are done.
            List<RaceParticipant> riders = raceParticipantRepository
                    .findByRaceIdAndRoleIn(race.getId(), java.util.List.of("host", "rider"));
            boolean allDone = !riders.isEmpty() && riders.stream()
                    .allMatch(p -> "finished".equals(p.getStatus()) || "dnf".equals(p.getStatus()));
            if (allDone && "in_progress".equals(race.getStatus())) {
                race.setStatus("completed");
                race.setEndedAt(java.time.LocalDateTime.now());
                raceRepository.save(race);
            }
        } catch (Exception ignored) {}
    }

    /**
     * The real moment a rider crossed the finish line on their final
     * (target) lap. Derived from the persisted lap whose {@code lapNumber}
     * equals the ride's target laps; that lap's {@code endTime} comes from
     * the GPS point's {@code capturedAtMs}, so it reflects the actual
     * crossing time regardless of when the point was uploaded. Falls back
     * to the latest lap's end time, then the ride's end time.
     */
    private LocalDateTime raceFinishInstant(RideRecord ride) {
        if (ride == null) return null;
        List<RideLap> laps = rideLapRepository.findByRideIdOrderByLapNumberAsc(ride.getId());
        Integer target = ride.getTargetLaps();
        if (target != null && target > 0) {
            for (RideLap lap : laps) {
                if (target.equals(lap.getLapNumber()) && lap.getEndTime() != null) {
                    return lap.getEndTime();
                }
            }
        }
        for (int i = laps.size() - 1; i >= 0; i--) {
            if (laps.get(i).getEndTime() != null) return laps.get(i).getEndTime();
        }
        return ride.getEndTime();
    }

    /**
     * Recompute {@code finishRank} for every finished participant of a race
     * by ordering them on their real finish-line crossing time (earliest =
     * rank 1). This makes ranking independent of the order in which each
     * rider's finishing GPS batch happens to reach the server (5 s batched
     * uploads + live-poll cadence can deliver finish points out of order).
     * Idempotent and self-correcting: re-running after every finish settles
     * all ranks to true crossing order. Ties (equal crossing instant) are
     * broken deterministically by ride id.
     */
    @Transactional
    public void recomputeFinishRanksByTime(Long raceId) {
        if (raceId == null) return;
        List<RaceParticipant> finished = raceParticipantRepository
                .findByRaceIdAndRoleIn(raceId, java.util.List.of("host", "rider"))
                .stream()
                .filter(p -> "finished".equals(p.getStatus()) && p.getRide() != null)
                .sorted((a, b) -> {
                    LocalDateTime ta = raceFinishInstant(a.getRide());
                    LocalDateTime tb = raceFinishInstant(b.getRide());
                    if (ta == null && tb == null) {
                        return Long.compare(a.getRide().getId(), b.getRide().getId());
                    }
                    if (ta == null) return 1;   // unknown finish time sorts last
                    if (tb == null) return -1;
                    int c = ta.compareTo(tb);
                    if (c != 0) return c;
                    return Long.compare(a.getRide().getId(), b.getRide().getId());
                })
                .toList();
        int rank = 1;
        for (RaceParticipant p : finished) {
            Integer newRank = rank++;
            if (!newRank.equals(p.getFinishRank())) {
                p.setFinishRank(newRank);
                raceParticipantRepository.save(p);
            }
        }
    }

    /**
     * For each user checkpoint, find the FIRST point in the lap that lies
     * within {@link #CHECKPOINT_PASS_KM} of it; record (sequenceIndex, ts,
     * lat, lng). Multiple checkpoints can share their pass-source point if
     * they are physically close.
     */
    private List<Object[]> extractLapPasses(List<RidePoint> lapPoints,
                                            List<UserCheckpoint> checkpoints) {
        if (lapPoints.isEmpty() || checkpoints.isEmpty()) return List.of();
        List<Object[]> out = new ArrayList<>();
        for (UserCheckpoint cp : checkpoints) {
            for (RidePoint p : lapPoints) {
                if (p.getTimestamp() == null) continue;
                double d = GeoUtils.haversineKm(
                        cp.getLatitude(), cp.getLongitude(),
                        p.getLatitude(), p.getLongitude());
                if (d <= CHECKPOINT_PASS_KM) {
                    out.add(new Object[]{cp.getSequenceIndex(), p.getTimestamp(),
                            p.getLatitude(), p.getLongitude()});
                    break;
                }
            }
        }
        return out;
    }

    private void persistLapPasses(List<RideLap> laps, List<List<Object[]>> passesPerLap) {
        if (laps.size() != passesPerLap.size()) return;
        List<RideLapCheckpoint> toSave = new ArrayList<>();
        for (int i = 0; i < laps.size(); i++) {
            RideLap lap = laps.get(i);
            for (Object[] entry : passesPerLap.get(i)) {
                RideLapCheckpoint c = new RideLapCheckpoint();
                c.setLapId(lap.getId());
                c.setSequenceIndex((Integer) entry[0]);
                c.setPassTime((LocalDateTime) entry[1]);
                c.setLatitude((Double) entry[2]);
                c.setLongitude((Double) entry[3]);
                toSave.add(c);
            }
        }
        if (!toSave.isEmpty()) rideLapCheckpointRepository.saveAll(toSave);
    }

    /**
     * Calculate what percentage of the trail is "covered" by the ride points.
     * The trail is resampled into ~20m sample points. Each sample point counts
     * as covered if any ride point lies within OVERLAP_THRESHOLD_KM.
     */
    private double calculateOverlap(List<RidePoint> ridePoints, List<TrailPoint> trailPoints) {
        if (trailPoints.size() < 2 || ridePoints.isEmpty()) return 0.0;

        // Resample trail into ~20m sample points
        final double SAMPLE_INTERVAL_KM = 0.02; // 20 meters
        List<double[]> samplePoints = new ArrayList<>();
        for (int i = 0; i < trailPoints.size() - 1; i++) {
            TrailPoint a = trailPoints.get(i);
            TrailPoint b = trailPoints.get(i + 1);
            double segLen = GeoUtils.haversineKm(a.getLatitude(), a.getLongitude(),
                    b.getLatitude(), b.getLongitude());
            int samples = Math.max(1, (int) Math.ceil(segLen / SAMPLE_INTERVAL_KM));
            for (int s = 0; s < samples; s++) {
                double t = (double) s / samples;
                double lat = a.getLatitude() + (b.getLatitude() - a.getLatitude()) * t;
                double lng = a.getLongitude() + (b.getLongitude() - a.getLongitude()) * t;
                samplePoints.add(new double[]{lat, lng});
            }
        }
        // Add the very last trail point
        TrailPoint last = trailPoints.get(trailPoints.size() - 1);
        samplePoints.add(new double[]{last.getLatitude(), last.getLongitude()});

        if (samplePoints.isEmpty()) return 0.0;

        int covered = 0;
        for (double[] sp : samplePoints) {
            for (RidePoint rp : ridePoints) {
                double dist = GeoUtils.haversineKm(sp[0], sp[1], rp.getLatitude(), rp.getLongitude());
                if (dist <= OVERLAP_THRESHOLD_KM) {
                    covered++;
                    break;
                }
            }
        }

        double pct = (double) covered / samplePoints.size() * 100.0;
        return Math.round(pct * 10.0) / 10.0;
    }

    private void calculateFinalStats(RideRecord ride) {
        RideStatsDto stats = computeCurrentStats(ride);
        ride.setDistance(stats.getDistanceKm());
        ride.setAvgSpeed(stats.getAvgSpeedKmh());
        ride.setMaxSpeed(stats.getMaxSpeedKmh());
        ride.setElevation(stats.getElevationMeters());
    }
}
