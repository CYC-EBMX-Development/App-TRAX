package com.trax.controller;

import com.trax.dto.*;
import com.trax.model.User;
import com.trax.service.RaceService;
import org.springframework.data.domain.Page;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/races")
public class RaceController {

    private final RaceService raceService;

    public RaceController(RaceService raceService) {
        this.raceService = raceService;
    }

    /** Create a new race (host) */
    @PostMapping
    public ResponseEntity<ApiResponse<RaceDto>> createRace(
            Authentication auth, @RequestBody CreateRaceRequest request) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.createRace(user.getId(), request)));
    }

    /** Get race details */
    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<RaceDto>> getRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.getRace(id, user.getId())));
    }

    /** Join race as rider */
    @PostMapping("/{id}/join")
    public ResponseEntity<ApiResponse<RaceDto>> joinRace(
            Authentication auth, @PathVariable Long id,
            @RequestBody(required = false) JoinRaceRequest request) {
        User user = (User) auth.getPrincipal();
        Long bikeId = request != null ? request.getBicycleId() : null;
        return ResponseEntity.ok(ApiResponse.success(
                raceService.joinRace(id, user.getId(), bikeId)));
    }

    /** Join race by code */
    @PostMapping("/join-by-code")
    public ResponseEntity<ApiResponse<RaceDto>> joinByCode(
            Authentication auth, @RequestBody JoinByCodeRequest request) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.joinByCode(request.getJoinCode(), user.getId(),
                        request.getRole(), request.getBicycleId())));
    }

    /** Observe a race */
    @PostMapping("/{id}/observe")
    public ResponseEntity<ApiResponse<RaceDto>> observeRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.observeRace(id, user.getId())));
    }

    /** Update race type (public/private), host only */
    @PostMapping("/{id}/type")
    public ResponseEntity<ApiResponse<RaceDto>> updateRaceType(
            Authentication auth, @PathVariable Long id,
            @RequestBody java.util.Map<String, Boolean> body) {
        User user = (User) auth.getPrincipal();
        Boolean isPublic = body.get("isPublic");
        if (isPublic == null) throw new RuntimeException("isPublic is required");
        return ResponseEntity.ok(ApiResponse.success(
                raceService.updateRaceType(id, user.getId(), isPublic)));
    }

    /** Update race settings (trail, laps, max participants, schedule), host only */
    @PostMapping("/{id}/settings")
    public ResponseEntity<ApiResponse<RaceDto>> updateRaceSettings(
            Authentication auth, @PathVariable Long id,
            @RequestBody java.util.Map<String, Object> body) {
        User user = (User) auth.getPrincipal();
        Long trailId = body.get("trailId") != null
                ? ((Number) body.get("trailId")).longValue() : null;
        Integer targetLaps = body.get("targetLaps") != null
                ? ((Number) body.get("targetLaps")).intValue() : null;
        Integer maxParticipants = body.get("maxParticipants") != null
                ? ((Number) body.get("maxParticipants")).intValue() : null;
        String scheduledTime = body.containsKey("scheduledTime")
                ? (body.get("scheduledTime") == null ? "" : body.get("scheduledTime").toString())
                : null;
        return ResponseEntity.ok(ApiResponse.success(
                raceService.updateRaceSettings(id, user.getId(),
                        trailId, targetLaps, maxParticipants, scheduledTime)));
    }

    /** Quit race (rider/observer, not host) */
    @PostMapping("/{id}/quit")
    public ResponseEntity<ApiResponse<String>> quitRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        raceService.quitRace(id, user.getId());
        return ResponseEntity.ok(ApiResponse.success("Left the race"));
    }

    /** Start race (host only) → preparing phase */
    @PostMapping("/{id}/start")
    public ResponseEntity<ApiResponse<RaceDto>> startRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.startRace(id, user.getId())));
    }

    /** Rider marks themselves as ready */
    @PostMapping("/{id}/ready")
    public ResponseEntity<ApiResponse<RaceDto>> readyForRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.readyForRace(id, user.getId())));
    }

    /** Set or change bicycle for a race participant */
    @PostMapping("/{id}/set-bike")
    public ResponseEntity<ApiResponse<RaceDto>> setBike(
            Authentication auth, @PathVariable Long id,
            @RequestBody java.util.Map<String, Long> body) {
        User user = (User) auth.getPrincipal();
        Long bicycleId = body.get("bicycleId");
        return ResponseEntity.ok(ApiResponse.success(
                raceService.setBike(id, user.getId(), bicycleId)));
    }

    /** Report rider GPS location during preparing phase */
    @PostMapping("/{id}/location")
    public ResponseEntity<ApiResponse<String>> reportLocation(
            Authentication auth, @PathVariable Long id,
            @RequestBody java.util.Map<String, Double> body) {
        User user = (User) auth.getPrincipal();
        Double lat = body.get("latitude");
        Double lng = body.get("longitude");
        if (lat == null || lng == null) throw new RuntimeException("latitude and longitude required");
        raceService.updateLocation(id, user.getId(), lat, lng);
        return ResponseEntity.ok(ApiResponse.success("Location updated"));
    }

    /** Go! Start the actual race (host only) → in_progress */
    @PostMapping("/{id}/go")
    public ResponseEntity<ApiResponse<RaceDto>> goRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.goRace(id, user.getId())));
    }

    /** Stop race (host only) */
    @PostMapping("/{id}/stop")
    public ResponseEntity<ApiResponse<RaceDto>> stopRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.stopRace(id, user.getId())));
    }

    /** Cancel race (host only) */
    @PostMapping("/{id}/cancel")
    public ResponseEntity<ApiResponse<RaceDto>> cancelRace(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.cancelRace(id, user.getId())));
    }

    /** Get live race data (positions + stats) */
    @GetMapping("/{id}/live")
    public ResponseEntity<ApiResponse<RaceLiveDto>> getLiveData(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.getLiveData(id, user.getId())));
    }

    /** List public races available to join */
    @GetMapping("/public")
    public ResponseEntity<ApiResponse<List<RaceDto>>> getPublicRaces(Authentication auth) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.getPublicRaces(user.getId())));
    }

    /** List public races available to observe */
    @GetMapping("/public/observe")
    public ResponseEntity<ApiResponse<List<RaceDto>>> getPublicRacesForObserver(
            Authentication auth) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.getPublicRacesForObserver(user.getId())));
    }

    /** Get upcoming events for current user (max 3) */
    @GetMapping("/upcoming")
    public ResponseEntity<ApiResponse<List<RaceDto>>> getUpcomingEvents(Authentication auth) {
        User user = (User) auth.getPrincipal();
        List<RaceDto> events = raceService.getUpcomingEvents(user.getId());
        // Return at most 3
        if (events.size() > 3) events = events.subList(0, 3);
        return ResponseEntity.ok(ApiResponse.success(events));
    }

    /** Get all events for current user (paginated) */
    @GetMapping("/my-events")
    public ResponseEntity<ApiResponse<Page<RaceDto>>> getMyEvents(
            Authentication auth,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                raceService.getMyEvents(user.getId(), page, size)));
    }

    // ── Inner DTOs ──────────────────────────────────────

    public static class JoinRaceRequest {
        private Long bicycleId;
        public Long getBicycleId() { return bicycleId; }
        public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    }

    public static class JoinByCodeRequest {
        private String joinCode;
        private String role;  // rider or observer
        private Long bicycleId;
        public String getJoinCode() { return joinCode; }
        public void setJoinCode(String joinCode) { this.joinCode = joinCode; }
        public String getRole() { return role; }
        public void setRole(String role) { this.role = role; }
        public Long getBicycleId() { return bicycleId; }
        public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    }
}
