package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.TrailCreateRequest;
import com.trax.dto.TrailDto;
import com.trax.model.Trail;
import com.trax.model.User;
import com.trax.service.TrailService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/trails")
public class TrailController {
    private final TrailService trailService;

    public TrailController(TrailService trailService) {
        this.trailService = trailService;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<TrailDto>>> getAllTrails(Authentication auth) {
        User user = (User) auth.getPrincipal();
        List<TrailDto> dtos = trailService.getVisibleTrails(user.getId());
        return ResponseEntity.ok(ApiResponse.success(dtos));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<TrailDto>> getTrailById(@PathVariable Long id) {
        return ResponseEntity.ok(ApiResponse.success(
                TrailDto.fromEntity(trailService.getTrailById(id))));
    }

    @PostMapping("/create")
    public ResponseEntity<ApiResponse<TrailDto>> createTrailFromRecording(
            Authentication auth,
            @RequestBody TrailCreateRequest request) {
        User user = (User) auth.getPrincipal();
        try {
            TrailDto dto = trailService.createTrailFromRecording(user.getId(), request);
            return ResponseEntity.ok(ApiResponse.success(dto));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(ApiResponse.error(400, e.getMessage()));
        }
    }

    /**
     * Backfill thumbnails for trails whose imageUrl is null/empty.
     * Safe to call repeatedly — only generates the missing ones.
     */
    @PostMapping("/backfill-thumbnails")
    public ResponseEntity<ApiResponse<Map<String, Object>>> backfillThumbnails() {
        return ResponseEntity.ok(
                ApiResponse.success(trailService.backfillMissingThumbnails()));
    }

    @GetMapping("/{id}/points")
    public ResponseEntity<ApiResponse<List<Map<String, Object>>>> getTrailPoints(@PathVariable Long id) {
        List<Map<String, Object>> points = trailService.getTrailPoints(id).stream()
                .map(p -> Map.<String, Object>of(
                        "latitude", p.getLatitude(),
                        "longitude", p.getLongitude(),
                        "altitude", p.getAltitude(),
                        "sequenceIndex", p.getSequenceIndex()
                ))
                .toList();
        return ResponseEntity.ok(ApiResponse.success(points));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<String>> deleteTrail(Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        try {
            trailService.deleteTrail(id, user.getId());
            return ResponseEntity.ok(ApiResponse.success("Trail deleted"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(ApiResponse.error(403, e.getMessage()));
        }
    }

    @PatchMapping("/{id}/visibility")
    public ResponseEntity<ApiResponse<TrailDto>> updateTrailVisibility(
            Authentication auth,
            @PathVariable Long id,
            @RequestBody Map<String, Boolean> body) {
        User user = (User) auth.getPrincipal();
        boolean isPublic = body.getOrDefault("isPublic", true);
        try {
            Trail trail = trailService.updateTrailVisibility(id, user.getId(), isPublic);
            return ResponseEntity.ok(ApiResponse.success(TrailDto.fromEntity(trail)));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(ApiResponse.error(403, e.getMessage()));
        }
    }
}
