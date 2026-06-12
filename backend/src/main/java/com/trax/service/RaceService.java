package com.trax.service;

import com.trax.dto.*;
import com.trax.model.*;
import com.trax.repository.*;
import com.trax.signal.LocationIngestService;
import com.trax.signal.SignalSource;
import com.trax.signal.UnifiedLocationFrame;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.ZoneId;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;

@Service
public class RaceService {

    private static final Logger log = LoggerFactory.getLogger(RaceService.class);
    private static final int LIVE_ALIGNMENT_RESOLUTION_MS = 1000;

    private final RaceRepository raceRepo;
    private final RaceParticipantRepository participantRepo;
    private final RideService rideService;
    private final UserRepository userRepo;
    private final TrailRepository trailRepo;
    private final BicycleRepository bikeRepo;
    private final RideRecordRepository rideRecordRepo;
    private final RidePointRepository pointRepo;
    private final RideLapRepository lapRepo;
    private final LocationIngestService locationIngestService;

    public RaceService(RaceRepository raceRepo,
                       RaceParticipantRepository participantRepo,
                       RideService rideService,
                       UserRepository userRepo,
                       TrailRepository trailRepo,
                       BicycleRepository bikeRepo,
                       RideRecordRepository rideRecordRepo,
                       RidePointRepository pointRepo,
                       RideLapRepository lapRepo,
                       LocationIngestService locationIngestService) {
        this.raceRepo = raceRepo;
        this.participantRepo = participantRepo;
        this.rideService = rideService;
        this.userRepo = userRepo;
        this.trailRepo = trailRepo;
        this.bikeRepo = bikeRepo;
        this.rideRecordRepo = rideRecordRepo;
        this.pointRepo = pointRepo;
        this.lapRepo = lapRepo;
        this.locationIngestService = locationIngestService;
    }

    // ── Create Race ──────────────────────────────────────

    @Transactional
    public RaceDto createRace(Long userId, CreateRaceRequest req) {
        User user = userRepo.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
        Trail trail = trailRepo.findById(req.getTrailId())
                .orElseThrow(() -> new RuntimeException("Trail not found"));

        Race race = new Race();
        race.setHost(user);
        race.setTrail(trail);
        race.setName(req.getName());
        race.setMaxParticipants(req.getMaxParticipants() != null ? req.getMaxParticipants() : 10);
        race.setTargetLaps(req.getTargetLaps() != null ? req.getTargetLaps() : 1);
        race.setPublic(req.getIsPublic() != null ? req.getIsPublic() : true);
        race.setNotes(req.getNotes());
        race.setJoinCode(generateJoinCode());
        race.setStatus("waiting");
        String gt = req.getGameType() == null ? "RACE" : req.getGameType().toUpperCase();
        if (!"RACE".equals(gt) && !"LAPS".equals(gt)) gt = "RACE";
        race.setGameType(gt);

        if (req.getScheduledTime() != null) {
            race.setScheduledTime(LocalDateTime.parse(req.getScheduledTime()));
        }

        race = raceRepo.save(race);

        // Host auto-joins as participant with role "host"
        RaceParticipant hostP = new RaceParticipant();
        hostP.setRace(race);
        hostP.setUser(user);
        hostP.setRole("host");
        hostP.setStatus("joined");
        if (req.getBicycleId() != null) {
            Bicycle bike = bikeRepo.findById(req.getBicycleId()).orElse(null);
            if (bike != null && bike.getOwner().getId().equals(userId)) {
                hostP.setBicycle(bike);
            }
        }
        participantRepo.save(hostP);

        List<RaceParticipant> participants = participantRepo.findByRaceId(race.getId());
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Get Race by ID ───────────────────────────────────

    public RaceDto getRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        List<RaceParticipant> participants = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Join Race ────────────────────────────────────────

    @Transactional
    public RaceDto joinRace(Long raceId, Long userId, Long bicycleId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!"waiting".equals(race.getStatus())) {
            throw new RuntimeException("Race is not open for joining");
        }
        if (participantRepo.existsByRaceIdAndUserId(raceId, userId)) {
            throw new RuntimeException("Already joined this race");
        }
        long riderCount = participantRepo.countByRaceIdAndRoleIn(raceId, List.of("host", "rider"));
        if (riderCount >= race.getMaxParticipants()) {
            throw new RuntimeException("Race is full");
        }

        RaceParticipant p = new RaceParticipant();
        p.setRace(race);
        p.setUser(userRepo.findById(userId).orElseThrow());
        p.setRole("rider");
        p.setStatus("joined");
        if (bicycleId != null) {
            Bicycle bike = bikeRepo.findById(bicycleId).orElse(null);
            if (bike != null && bike.getOwner().getId().equals(userId)) {
                p.setBicycle(bike);
            }
        }
        participantRepo.save(p);

        List<RaceParticipant> participants = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Join by Code ─────────────────────────────────────

    @Transactional
    public RaceDto joinByCode(String joinCode, Long userId, String role, Long bicycleId) {
        // Match only unstarted events. Codes are recyclable after a race
        // ends, so a completed race with the same code must be ignored.
        String code = joinCode == null ? "" : joinCode.trim();
        Race race = raceRepo.findUnstartedByJoinCode(code)
                .orElseThrow(() -> new RuntimeException("Invalid join code"));
        if ("observer".equals(role)) {
            return observeRace(race.getId(), userId);
        }
        return joinRace(race.getId(), userId, bicycleId);
    }

    // ── Observe Race ─────────────────────────────────────

    @Transactional
    public RaceDto observeRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if ("canceled".equals(race.getStatus()) || "completed".equals(race.getStatus())) {
            throw new RuntimeException("Race is not active");
        }
        if (participantRepo.existsByRaceIdAndUserId(raceId, userId)) {
            throw new RuntimeException("Already participating in this race");
        }

        RaceParticipant p = new RaceParticipant();
        p.setRace(race);
        p.setUser(userRepo.findById(userId).orElseThrow());
        p.setRole("observer");
        p.setStatus("joined");
        participantRepo.save(p);

        List<RaceParticipant> participants = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Quit Race (rider/observer, not host) ────────────

    @Transactional
    public void quitRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        RaceParticipant p = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElseThrow(() -> new RuntimeException("You are not in this race"));
        if ("host".equals(p.getRole())) {
            throw new RuntimeException("Host cannot quit. Cancel the race instead.");
        }
        if ("in_progress".equals(race.getStatus())) {
            throw new RuntimeException("Cannot quit while race is in progress");
        }
        participantRepo.delete(p);
    }

    // ── Update Race Settings (host only, before in_progress) ─────

    @Transactional
    public RaceDto updateRaceSettings(Long raceId, Long userId,
                                      Long trailId,
                                      Integer targetLaps,
                                      Integer maxParticipants,
                                      String scheduledTimeIso) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can update settings");
        }
        if (!"waiting".equals(race.getStatus()) && !"preparing".equals(race.getStatus())) {
            throw new RuntimeException("Can only update settings before race starts");
        }

        if (trailId != null) {
            Trail trail = trailRepo.findById(trailId)
                    .orElseThrow(() -> new RuntimeException("Trail not found"));
            race.setTrail(trail);
        }
        if (targetLaps != null) {
            if (targetLaps < 1 || targetLaps > 100) {
                throw new RuntimeException("Target laps must be between 1 and 100");
            }
            race.setTargetLaps(targetLaps);
        }
        if (maxParticipants != null) {
            int currentCount = participantRepo
                    .findByRaceIdAndRoleIn(raceId, List.of("host", "rider"))
                    .size();
            if (maxParticipants < 2 || maxParticipants > 50) {
                throw new RuntimeException("Max participants must be between 2 and 50");
            }
            if (maxParticipants < currentCount) {
                throw new RuntimeException("Max participants cannot be less than current riders");
            }
            race.setMaxParticipants(maxParticipants);
        }
        if (scheduledTimeIso != null) {
            if (scheduledTimeIso.isEmpty()) {
                race.setScheduledTime(null);
            } else {
                try {
                    race.setScheduledTime(LocalDateTime.parse(scheduledTimeIso));
                } catch (Exception e) {
                    throw new RuntimeException("Invalid scheduled time");
                }
            }
        }

        raceRepo.save(race);
        List<RaceParticipant> participants = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Update Race Type (host only) ─────────────────────

    @Transactional
    public RaceDto updateRaceType(Long raceId, Long userId, boolean isPublic) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can update race type");
        }
        if (!"waiting".equals(race.getStatus()) && !"preparing".equals(race.getStatus())) {
            throw new RuntimeException("Can only change type while waiting or preparing");
        }
        race.setPublic(isPublic);
        raceRepo.save(race);
        List<RaceParticipant> participants = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, participants, userId);
    }

    // ── Start Race (host only) → preparing ────────────────

    @Transactional
    public RaceDto startRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can start the race");
        }
        if (!"waiting".equals(race.getStatus())) {
            throw new RuntimeException("Race cannot be started");
        }

        race.setStatus("preparing");
        raceRepo.save(race);

        List<RaceParticipant> all = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, all, userId);
    }

    // ── Ready (rider marks themselves ready) ─────────────

    @Transactional
    public RaceDto readyForRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!"preparing".equals(race.getStatus())) {
            throw new RuntimeException("Race is not in preparing phase");
        }
        RaceParticipant p = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElseThrow(() -> new RuntimeException("You are not in this race"));
        if (!"joined".equals(p.getStatus())) {
            throw new RuntimeException("Already ready or racing");
        }
        p.setStatus("ready");
        participantRepo.save(p);

        List<RaceParticipant> all = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, all, userId);
    }

    // ── Update Location (preparing lobby + in-progress race) ──────

    /**
     * Reports a participant's current GPS fix.
     *
     * <p>Two roles depending on race state:
     * <ul>
     *   <li><b>preparing</b>: only the lobby map needs the fix. We just
     *       store it on the {@link RaceParticipant} row so every other
     *       participant's live-data poll sees a fresh pin.</li>
     *   <li><b>in_progress</b>: the participant is racing, so the fix is
     *       also persisted as a {@link RidePoint} on their per-rider
     *       {@link RideRecord}. Without this, {@code detectAndPersistLaps}
     *       has no data to work with for race rides — race riders would
     *       never close a lap and {@link #checkAndFinishRider} would never
     *       fire. Lap detection + WS push then happen automatically via
     *       {@link RideService#detectLapsForRideId(Long)}, sharing the
     *       exact same finish-line / approach-direction / freeze-after-
     *       target rules as solo lap-timer rides.</li>
     * </ul>
     */
    /**
     * Live-map participant position ONLY — updates the participant's lat/lng so
     * other riders see them on the live map, but does NOT ingest a ride_point or
     * run lap detection.
     *
     * <p>Used by clients that drive their own dense GPS sampling through the
     * canonical {@code ActiveRideService} pipeline (phone {@code addRidePoints}
     * batch upload, or module MQTT). For those clients the dense points already
     * flow through {@link RideService#addPointsAndGetStats}, which runs
     * {@code detectAndPersistLaps} for rides that carry a trail + target laps
     * (race rides do). Re-ingesting here would create near-duplicate rows
     * (different capturedAtMs → dedup misses), so we deliberately skip it.</p>
     *
     * <p>The legacy {@link #updateLocation} path is kept for older app builds
     * that still rely on the 3 s GPS fix doubling as a ride_point.</p>
     */
    @Transactional
    public void updateParticipantPosition(Long raceId, Long userId, double latitude, double longitude) {
        RaceParticipant p = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElseThrow(() -> new RuntimeException("You are not in this race"));
        p.setLatitude(latitude);
        p.setLongitude(longitude);
        participantRepo.save(p);
    }

    @Transactional
    public void updateLocation(Long raceId, Long userId, double latitude, double longitude) {
        RaceParticipant p = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElseThrow(() -> new RuntimeException("You are not in this race"));
        p.setLatitude(latitude);
        p.setLongitude(longitude);
        participantRepo.save(p);

        // While racing, the same GPS fix doubles as a ride_point so the
        // shared lap-detection pipeline (RideService.detectAndPersistLaps)
        // can run. We ONLY do this for phone-source race rides
        // (mode != with_module): module-bike riders already have their
        // ride_points written by the MQTT path (ModuleTelemetryService
        // → ingestModule → RideRecordRepository.findRideCoveringTime),
        // and writing again here would create duplicate-but-not-quite-
        // duplicate rows (different capturedAtMs → dedup misses).
        // Lobby lat/lng above still updates for ALL riders so other
        // participants see them on the live map regardless of source.
        RideRecord ride = p.getRide();
        if (ride != null
                && "racing".equals(p.getStatus())
                && "active".equals(ride.getStatus())
                && !"with_module".equals(ride.getMode())) {
            try {
                UnifiedLocationFrame frame = new UnifiedLocationFrame(
                        System.currentTimeMillis(),
                        latitude,
                        longitude,
                        null,           // altitude not reported on this endpoint
                        null,           // speed derived later from successive points
                        null,           // heading
                        null,           // hdop
                        SignalSource.PHONE,
                        "race:" + raceId + ":user:" + userId);
                locationIngestService.ingestPhone(ride, frame).ifPresent(rp -> {
                    try {
                        rideService.detectLapsForRideId(ride.getId());
                    } catch (Exception ex) {
                        log.warn("race lap detect failed rideId={} : {}",
                                ride.getId(), ex.toString());
                    }
                });
            } catch (Exception ex) {
                // Best-effort: do not fail the location report if ingest
                // or detection throws. The next 3 s tick will retry.
                log.warn("race ride_point ingest failed rideId={} userId={} : {}",
                        ride.getId(), userId, ex.toString());
            }
        }
    }

    // ── Go Race (host only) → in_progress ────────────────

    @Transactional
    public RaceDto goRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can start the race");
        }
        if (!"preparing".equals(race.getStatus())) {
            throw new RuntimeException("Race is not in preparing phase");
        }

        race.setStatus("in_progress");
        race.setStartedAt(LocalDateTime.now());
        raceRepo.save(race);

        // Create a RideRecord for each rider (host + riders)
        List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
                raceId, List.of("host", "rider"));
        for (RaceParticipant rp : riders) {
            RideStartRequest rideReq = new RideStartRequest();
            // Find rider's first bike
            List<Bicycle> bikes = bikeRepo.findByOwnerIdOrderByCreatedAtDesc(rp.getUser().getId());
            Bicycle riderBike = null;
            if (!bikes.isEmpty()) {
                riderBike = bikes.get(0);
                rideReq.setBicycleId(riderBike.getId());
            }
            // Per-rider source: module bike (traxSerialNumber present) feeds
            // its RideRecord directly via MQTT → LocationIngestService.
            // ingestModule, which finds the covering ride by bike+time via
            // RideRecordRepository.findRideCoveringTime (mode-agnostic).
            // Phone-only riders fall back to the existing
            // /api/races/{id}/location → ingestPhone path inside
            // RaceService.updateLocation.
            boolean hasModule = riderBike != null
                    && riderBike.getTraxSerialNumber() != null
                    && !riderBike.getTraxSerialNumber().isBlank();
            rideReq.setMode(hasModule ? "with_module" : "without_module");
            rideReq.setTrailId(race.getTrail().getId());
            rideReq.setTargetLaps(race.getTargetLaps());

            RideRecordDto rideDto = rideService.startRide(rp.getUser().getId(), rideReq);
            // Link ride to participant and mark as race source
            RideRecord ride = rideRecordRepo.findById(rideDto.getId()).orElse(null);
            if (ride != null) {
                ride.setSource("race");
                rideRecordRepo.save(ride);
            }
            rp.setRide(ride);
            rp.setStatus("racing");
            participantRepo.save(rp);
        }

        List<RaceParticipant> all = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, all, userId);
    }

    // ── Stop Race (host only) ────────────────────────────

    @Transactional
    public RaceDto stopRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can stop the race");
        }
        if (!"in_progress".equals(race.getStatus())) {
            throw new RuntimeException("Race is not in progress");
        }

        // Stop all active rides, mark unfinished riders as DNF
        List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
                raceId, List.of("host", "rider"));
        for (RaceParticipant rp : riders) {
            if ("racing".equals(rp.getStatus()) && rp.getRide() != null) {
                // (ModuleSimulatorService removed — real module data flows
                //  via MQTT/BLE relay; race rides no longer need a sim stop.)

                // Remove laps with no completed full lap
                RideRecord ride = rp.getRide();
                Integer completed = ride.getCompletedLaps();
                if (completed == null || completed == 0) {
                    // No completed laps → DNF, delete all lap data
                    lapRepo.deleteAll(lapRepo.findByRideIdOrderByLapNumberAsc(ride.getId()));
                }
                try {
                    rideService.stopRide(ride.getId(), rp.getUser().getId());
                } catch (Exception ignored) {}
                rp.setStatus("dnf");
                participantRepo.save(rp);
            }
        }

        race.setStatus("completed");
        race.setEndedAt(LocalDateTime.now());
        raceRepo.save(race);

        List<RaceParticipant> all = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, all, userId);
    }

    // ── Cancel Race (host only) ──────────────────────────

    @Transactional
    public RaceDto cancelRace(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!race.getHost().getId().equals(userId)) {
            throw new RuntimeException("Only host can cancel the race");
        }
        if ("completed".equals(race.getStatus()) || "canceled".equals(race.getStatus())) {
            throw new RuntimeException("Race cannot be canceled");
        }

        // If in_progress, stop all rides
        if ("in_progress".equals(race.getStatus())) {
            List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
                    raceId, List.of("host", "rider"));
            for (RaceParticipant rp : riders) {
                if (rp.getRide() != null && "racing".equals(rp.getStatus())) {
                    try {
                        rideService.stopRide(rp.getRide().getId(), rp.getUser().getId());
                    } catch (Exception ignored) {}
                }
                rp.setStatus("dnf");
                participantRepo.save(rp);
            }
        }

        // If preparing, reset all participants back
        if ("preparing".equals(race.getStatus())) {
            List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
                    raceId, List.of("host", "rider"));
            for (RaceParticipant rp : riders) {
                rp.setStatus("dnf");
                participantRepo.save(rp);
            }
        }

        race.setStatus("canceled");
        race.setEndedAt(LocalDateTime.now());
        raceRepo.save(race);

        List<RaceParticipant> all = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, all, userId);
    }

    // ── Finish rider ─────────────────────────────────────

    @Transactional
    public void checkAndFinishRider(Long raceId, Long userId) {
        RaceParticipant rp = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElse(null);
        if (rp == null || !"racing".equals(rp.getStatus()) || rp.getRide() == null) return;

        Race race = rp.getRace();
        RideRecord ride = rp.getRide();
        if (ride.getCompletedLaps() != null &&
            ride.getCompletedLaps() >= race.getTargetLaps()) {
            // Rider finished all laps. (ModuleSimulatorService removed — no
            //  sim ticker to stop; real module telemetry stops on its own.)
            try {
                rideService.stopRide(ride.getId(), userId);
            } catch (Exception ignored) {}

            rp.setStatus("finished");
            participantRepo.save(rp);
            // Rank by REAL finish time (target-lap crossing instant), not by
            // detection order. 5 s batched uploads + live-poll cadence can
            // deliver two riders' finish points out of order, so the first
            // point to reach the server is not necessarily the first to
            // cross the line. recomputeFinishRanksByTime is idempotent and
            // re-sorts all finishers on their true crossing time.
            rideService.recomputeFinishRanksByTime(raceId);

            // Check if all riders finished
            checkAllFinished(raceId);
        }
    }

    private void checkAllFinished(Long raceId) {
        List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
                raceId, List.of("host", "rider"));
        boolean allDone = riders.stream()
                .allMatch(p -> "finished".equals(p.getStatus()) || "dnf".equals(p.getStatus()));
        if (allDone) {
            Race race = raceRepo.findById(raceId).orElse(null);
            if (race != null && "in_progress".equals(race.getStatus())) {
                race.setStatus("completed");
                race.setEndedAt(LocalDateTime.now());
                raceRepo.save(race);
            }
        }
    }

    // ── Set Bike ──────────────────────────────────────────

    @Transactional
    public RaceDto setBike(Long raceId, Long userId, Long bicycleId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
        if (!("waiting".equals(race.getStatus()) || "preparing".equals(race.getStatus()))) {
            throw new RuntimeException("Can only change bike before race starts");
        }
        RaceParticipant rp = participantRepo.findByRaceIdAndUserId(raceId, userId)
                .orElseThrow(() -> new RuntimeException("Not a participant"));
        if (bicycleId != null) {
            Bicycle bike = bikeRepo.findById(bicycleId)
                    .orElseThrow(() -> new RuntimeException("Bicycle not found"));
            if (!bike.getOwner().getId().equals(userId)) {
                throw new RuntimeException("Not your bicycle");
            }
            rp.setBicycle(bike);
        } else {
            rp.setBicycle(null);
        }
        participantRepo.save(rp);
        List<RaceParticipant> parts = participantRepo.findByRaceId(raceId);
        return RaceDto.fromEntity(race, parts, userId);
    }

    // ── Live Data ────────────────────────────────────────

    public RaceLiveDto getLiveData(Long raceId, Long userId) {
        Race race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));

        RaceLiveDto dto = new RaceLiveDto();
        dto.setRaceId(raceId);
        dto.setRaceStatus(race.getStatus());
        dto.setGameType(race.getGameType());

        if (race.getStartedAt() != null) {
            LocalDateTime end = race.getEndedAt() != null ? race.getEndedAt() : LocalDateTime.now();
            dto.setElapsedSeconds(Duration.between(race.getStartedAt(), end).toSeconds());
        }

        List<RaceParticipant> riders = participantRepo.findByRaceIdAndRoleIn(
            raceId, List.of("host", "rider"));

        // Keep race progression in sync with latest points: compute stats/laps,
        // mark riders as finished when target laps reached, and auto-complete race.
        // We also recompute for `completed` races so any final laps that were not
        // detected at the moment the race transitioned (e.g. last GPS point of a
        // late-finisher arrived after race auto-completion) get persisted on the
        // next live-data fetch. detectAndPersistLaps is idempotent.
        if ("in_progress".equals(race.getStatus()) || "completed".equals(race.getStatus())) {
            for (RaceParticipant rp : riders) {
                if (rp.getRide() != null) {
                    rideService.computeRaceStats(rp.getRide());
                    if ("in_progress".equals(race.getStatus())) {
                        checkAndFinishRider(raceId, rp.getUser().getId());
                    }
                }
            }
            // Refresh race + participants after status transitions.
            race = raceRepo.findById(raceId)
                .orElseThrow(() -> new RuntimeException("Race not found"));
            dto.setRaceStatus(race.getStatus());
            riders = participantRepo.findByRaceIdAndRoleIn(
                raceId, List.of("host", "rider"));
        }

        List<RaceLiveDto.RiderLiveInfo> riderInfos = new ArrayList<>();
        Map<Long, List<RidePoint>> ridePointsByRider = new HashMap<>();
        for (RaceParticipant rp : riders) {
            RaceLiveDto.RiderLiveInfo info = new RaceLiveDto.RiderLiveInfo();
            info.setUserId(rp.getUser().getId());
            info.setUserName(rp.getUser().getName());
            info.setUserAvatarUrl(com.trax.util.AvatarUrls.versioned(rp.getUser()));
            info.setStatus(rp.getStatus());
            info.setFinishRank(rp.getFinishRank());

            if (rp.getBicycle() != null) {
                info.setBicycleId(rp.getBicycle().getId());
                info.setBicycleName(rp.getBicycle().getName());
                info.setBicycleImageUrl(rp.getBicycle().getImageUrl());
            }

            if (rp.getRide() != null) {
                info.setRideId(rp.getRide().getId());
                RideRecord ride = rp.getRide();

                // Recompute distance + detect laps from current ride points.
                RideStatsDto stats = rideService.computeRaceStats(ride);
                info.setDistanceKm(stats.getDistanceKm());
                info.setCompletedLaps(stats.getCompletedLaps() != null
                        ? stats.getCompletedLaps()
                        : (ride.getCompletedLaps() != null ? ride.getCompletedLaps() : 0));
                info.setDurationSeconds(stats.getDurationSeconds());

                // Latest position
                var points = pointRepo.findByRideIdOrderByCapturedAtMsAsc(ride.getId());
                ridePointsByRider.put(rp.getUser().getId(), points);
                if (!points.isEmpty()) {
                    RidePoint last = points.get(points.size() - 1);
                    info.setLatitude(last.getLatitude());
                    info.setLongitude(last.getLongitude());
                    info.setSpeed(last.getSpeed());
                    info.setLastCapturedAtMs(resolveCapturedAtMs(last));
                }

                // Route polyline — all ride points
                info.setRoute(points.stream()
                        .map(p -> new RaceLiveDto.PointDto(
                                p.getLatitude(),
                                p.getLongitude(),
                                resolveCapturedAtMs(p)))
                        .toList());

                // Laps (with checkpoint passes attached)
                var laps = lapRepo.findByRideIdOrderByLapNumberAsc(ride.getId());
                info.setLaps(rideService.mapLapsWithPasses(laps));

                // Best single-lap time (used by LAPS-mode ranking).
                Long bestSec = null;
                for (var lap : laps) {
                    Long d = lap.getDurationSeconds();
                    if (d != null && d > 0 && (bestSec == null || d < bestSec)) {
                        bestSec = d;
                    }
                }
                info.setBestLapSeconds(bestSec);
                if (bestSec != null && (rp.getBestLapSeconds() == null
                        || !bestSec.equals(rp.getBestLapSeconds()))) {
                    rp.setBestLapSeconds(bestSec);
                    participantRepo.save(rp);
                }
            } else {
                // No ride record yet (preparing phase) — use participant's reported location
                if (rp.getLatitude() != null && rp.getLongitude() != null) {
                    info.setLatitude(rp.getLatitude());
                    info.setLongitude(rp.getLongitude());
                }
                info.setRoute(List.of());
                info.setLaps(List.of());
            }
            riderInfos.add(info);
        }

        applyAlignedAggregation(dto, riderInfos, ridePointsByRider);

        // Sort: in LAPS mode rank by best single lap time ascending
        // (riders without a completed lap go last); in RACE mode use the
        // legacy finished/laps/distance ordering.
        boolean lapsMode = "LAPS".equalsIgnoreCase(race.getGameType());
        if (lapsMode) {
            riderInfos.sort((a, b) -> {
                Long ba = a.getBestLapSeconds();
                Long bb = b.getBestLapSeconds();
                if (ba == null && bb == null) {
                    int lapCmp = Integer.compare(
                            b.getCompletedLaps() != null ? b.getCompletedLaps() : 0,
                            a.getCompletedLaps() != null ? a.getCompletedLaps() : 0);
                    if (lapCmp != 0) return lapCmp;
                    return Double.compare(b.getDistanceKm(), a.getDistanceKm());
                }
                if (ba == null) return 1;
                if (bb == null) return -1;
                return Long.compare(ba, bb);
            });
        } else {
        // Sort by: finished first (by rank), then by completedLaps desc, then distance desc
        riderInfos.sort((a, b) -> {
            if ("finished".equals(a.getStatus()) && !"finished".equals(b.getStatus())) return -1;
            if (!"finished".equals(a.getStatus()) && "finished".equals(b.getStatus())) return 1;
            if ("finished".equals(a.getStatus()) && "finished".equals(b.getStatus())) {
                return Integer.compare(
                        a.getFinishRank() != null ? a.getFinishRank() : 999,
                        b.getFinishRank() != null ? b.getFinishRank() : 999);
            }
            int lapCmp = Integer.compare(
                    b.getCompletedLaps() != null ? b.getCompletedLaps() : 0,
                    a.getCompletedLaps() != null ? a.getCompletedLaps() : 0);
            if (lapCmp != 0) return lapCmp;
            return Double.compare(b.getDistanceKm(), a.getDistanceKm());
        });
        }

        dto.setRiders(riderInfos);
        return dto;
    }

    private void applyAlignedAggregation(RaceLiveDto dto,
                                         List<RaceLiveDto.RiderLiveInfo> riderInfos,
                                         Map<Long, List<RidePoint>> ridePointsByRider) {
        Long minMs = null;
        Long maxMs = null;
        Map<Long, Map<Long, RaceLiveDto.AlignedRiderPointDto>> frameMap = new TreeMap<>();

        for (RaceLiveDto.RiderLiveInfo rider : riderInfos) {
            List<RidePoint> points = ridePointsByRider.getOrDefault(rider.getUserId(), List.of());
            for (RidePoint point : points) {
                Long capturedAtMs = resolveCapturedAtMs(point);
                if (capturedAtMs == null) continue;
                minMs = minMs == null ? capturedAtMs : Math.min(minMs, capturedAtMs);
                maxMs = maxMs == null ? capturedAtMs : Math.max(maxMs, capturedAtMs);

                long bucket = bucketizeMs(capturedAtMs, LIVE_ALIGNMENT_RESOLUTION_MS);
                RaceLiveDto.AlignedRiderPointDto rp = new RaceLiveDto.AlignedRiderPointDto();
                rp.setUserId(rider.getUserId());
                rp.setLatitude(point.getLatitude());
                rp.setLongitude(point.getLongitude());
                rp.setSpeed(point.getSpeed());
                frameMap.computeIfAbsent(bucket, k -> new LinkedHashMap<>())
                        .put(rider.getUserId(), rp);
            }
        }

        dto.setTimelineResolutionMs(LIVE_ALIGNMENT_RESOLUTION_MS);
        dto.setTimelineStartMs(minMs);
        dto.setTimelineEndMs(maxMs);
        if (frameMap.isEmpty()) {
            dto.setAlignedFrames(List.of());
            return;
        }

        List<RaceLiveDto.AlignedFrameDto> frames = new ArrayList<>(frameMap.size());
        for (Map.Entry<Long, Map<Long, RaceLiveDto.AlignedRiderPointDto>> e : frameMap.entrySet()) {
            RaceLiveDto.AlignedFrameDto frame = new RaceLiveDto.AlignedFrameDto();
            frame.setCapturedAtMs(e.getKey());
            frame.setRiders(new ArrayList<>(e.getValue().values()));
            frames.add(frame);
        }
        dto.setAlignedFrames(frames);
    }

    private static Long resolveCapturedAtMs(RidePoint p) {
        if (p.getCapturedAtMs() != null) return p.getCapturedAtMs();
        if (p.getTimestamp() == null) return null;
        return p.getTimestamp().atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
    }

    private static long bucketizeMs(long tsMs, int resolutionMs) {
        if (resolutionMs <= 1) return tsMs;
        return (tsMs / resolutionMs) * resolutionMs;
    }

    // ── Listings ─────────────────────────────────────────

    public List<RaceDto> getPublicRaces(Long userId) {
        return raceRepo.findPublicRacesNotJoinedByUser(userId).stream()
                .map(r -> {
                    List<RaceParticipant> parts = participantRepo.findByRaceId(r.getId());
                    return RaceDto.fromEntity(r, parts, userId);
                }).toList();
    }

    public List<RaceDto> getPublicRacesForObserver(Long userId) {
        return raceRepo.findPublicRacesForObserver(userId).stream()
                .map(r -> {
                    List<RaceParticipant> parts = participantRepo.findByRaceId(r.getId());
                    return RaceDto.fromEntity(r, parts, userId);
                }).toList();
    }

    public List<RaceDto> getUpcomingEvents(Long userId) {
        return raceRepo.findUpcomingByUser(userId).stream()
                .map(r -> {
                    List<RaceParticipant> parts = participantRepo.findByRaceId(r.getId());
                    return RaceDto.fromEntity(r, parts, userId);
                }).toList();
    }

    public Page<RaceDto> getMyEvents(Long userId, int page, int size) {
        Page<Race> races = raceRepo.findAllByUser(userId, PageRequest.of(page, size));
        return races.map(r -> {
            List<RaceParticipant> parts = participantRepo.findByRaceId(r.getId());
            return RaceDto.fromEntity(r, parts, userId);
        });
    }

    // ── Helpers ──────────────────────────────────────────

    private String generateJoinCode() {
        // 6-digit numeric code. Uniqueness is enforced ONLY against
        // currently-unstarted events (waiting/preparing) so codes can be
        // recycled once a race starts or completes.
        String chars = "0123456789";
        for (int attempt = 0; attempt < 50; attempt++) {
            StringBuilder sb = new StringBuilder(6);
            for (int i = 0; i < 6; i++) {
                sb.append(chars.charAt(ThreadLocalRandom.current().nextInt(chars.length())));
            }
            String code = sb.toString();
            if (!raceRepo.existsUnstartedByJoinCode(code)) {
                return code;
            }
        }
        throw new RuntimeException("Failed to generate a unique join code");
    }
}
