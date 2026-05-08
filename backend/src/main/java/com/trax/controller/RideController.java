package com.trax.controller;

import com.trax.dto.*;
import com.trax.model.RideRecord;
import com.trax.model.User;
import com.trax.service.RideService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/rides")
public class RideController {
    private final RideService rideService;

    public RideController(RideService rideService) {
        this.rideService = rideService;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<RideRecordDto>>> getUserRides(Authentication auth) {
        User user = (User) auth.getPrincipal();
        List<RideRecordDto> dtos = rideService.getUserRides(user.getId()).stream()
                .map(rideService::toRideRecordDto)
                .toList();
        return ResponseEntity.ok(ApiResponse.success(dtos));
    }

    @GetMapping("/active")
    public ResponseEntity<ApiResponse<RideRecordDto>> getActiveRide(Authentication auth) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.getActiveRide(user.getId())));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<RideRecordDto>> getRideById(Authentication auth, @PathVariable Long id) {
        RideRecord ride = rideService.getRideById(id);
        return ResponseEntity.ok(ApiResponse.success(rideService.toRideRecordDto(ride)));
    }

    @PostMapping("/start")
    public ResponseEntity<ApiResponse<RideRecordDto>> startRide(
            Authentication auth, @RequestBody RideStartRequest request) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.startRide(user.getId(), request)));
    }

    @PutMapping("/{id}/pause")
    public ResponseEntity<ApiResponse<RideRecordDto>> pauseRide(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.pauseRide(id, user.getId())));
    }

    @PutMapping("/{id}/resume")
    public ResponseEntity<ApiResponse<RideRecordDto>> resumeRide(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.resumeRide(id, user.getId())));
    }

    @PutMapping("/{id}/stop")
    public ResponseEntity<ApiResponse<RideRecordDto>> stopRide(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.stopRide(id, user.getId())));
    }

    @PostMapping("/{id}/points")
    public ResponseEntity<ApiResponse<RideStatsDto>> addPoints(
            Authentication auth, @PathVariable Long id,
            @RequestBody RidePointBatchRequest request) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(
                rideService.addPointsAndGetStats(id, user.getId(), request)));
    }

    @GetMapping("/{id}/stats")
    public ResponseEntity<ApiResponse<RideStatsDto>> getStats(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.getStats(id, user.getId())));
    }

    @GetMapping("/{id}/points")
    public ResponseEntity<ApiResponse<List<RidePointDto>>> getPoints(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.getPoints(id, user.getId())));
    }

    @GetMapping("/{id}/laps")
    public ResponseEntity<ApiResponse<List<RideLapDto>>> getLaps(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(rideService.getLaps(id, user.getId())));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<String>> deleteRide(
            Authentication auth, @PathVariable Long id) {
        User user = (User) auth.getPrincipal();
        rideService.deleteRide(id, user.getId());
        return ResponseEntity.ok(ApiResponse.success("Ride deleted successfully"));
    }
}
