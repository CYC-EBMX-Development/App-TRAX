package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.UserCheckpointDto;
import com.trax.model.User;
import com.trax.service.UserCheckpointService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/checkpoints")
public class UserCheckpointController {
    private final UserCheckpointService service;

    public UserCheckpointController(UserCheckpointService service) {
        this.service = service;
    }

    @GetMapping("/trail/{trailId}")
    public ResponseEntity<ApiResponse<List<UserCheckpointDto>>> list(
            Authentication auth, @PathVariable Long trailId) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(service.list(user.getId(), trailId)));
    }

    @PostMapping("/trail/{trailId}")
    public ResponseEntity<ApiResponse<List<UserCheckpointDto>>> add(
            Authentication auth,
            @PathVariable Long trailId,
            @RequestBody Map<String, Object> body) {
        User user = (User) auth.getPrincipal();
        try {
            double lat = ((Number) body.get("latitude")).doubleValue();
            double lng = ((Number) body.get("longitude")).doubleValue();
            return ResponseEntity.ok(ApiResponse.success(
                    service.add(user.getId(), trailId, lat, lng)));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(ApiResponse.error(400, e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.ok(ApiResponse.error(400, "Invalid request"));
        }
    }

    @DeleteMapping("/{checkpointId}")
    public ResponseEntity<ApiResponse<List<UserCheckpointDto>>> delete(
            Authentication auth, @PathVariable Long checkpointId) {
        User user = (User) auth.getPrincipal();
        try {
            return ResponseEntity.ok(ApiResponse.success(
                    service.delete(user.getId(), checkpointId)));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(ApiResponse.error(404, e.getMessage()));
        }
    }
}
