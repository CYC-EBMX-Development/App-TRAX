package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.BicycleDto;
import com.trax.model.User;
import com.trax.repository.UserRepository;
import com.trax.security.JwtUtil;
import com.trax.service.BicycleService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.servlet.http.HttpServletRequest;
import java.util.List;

@RestController
@RequestMapping("/api/bikes")
public class BicycleController {
    private final BicycleService bicycleService;
    private final JwtUtil jwtUtil;
    private final UserRepository userRepository;

    public BicycleController(BicycleService bicycleService, JwtUtil jwtUtil, UserRepository userRepository) {
        this.bicycleService = bicycleService;
        this.jwtUtil = jwtUtil;
        this.userRepository = userRepository;
    }

    private Long getUserIdFromToken(HttpServletRequest request) {
        String authHeader = request.getHeader("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new IllegalArgumentException("Invalid or missing token");
        }
        String token = authHeader.substring(7);
        if (!jwtUtil.validateToken(token)) {
            throw new IllegalArgumentException("Invalid token");
        }
        String email = jwtUtil.extractEmail(token);
        return userRepository.findByEmail(email)
                .orElseGet(() -> {
                    // Auto-create user for testing
                    User newUser = new User();
                    newUser.setEmail(email);
                    newUser.setPassword("test");
                    newUser.setName("Test User");
                    return userRepository.save(newUser);
                })
                .getId();
    }

    @PostMapping
    public ResponseEntity<ApiResponse<BicycleDto>> createBike(
            @RequestBody BicycleDto bikeDto,
            HttpServletRequest request) {
        try {
            Long userId = getUserIdFromToken(request);
            BicycleDto result = bicycleService.createBike(userId, bikeDto);
            return ResponseEntity.ok(ApiResponse.success(result));
        } catch (Exception e) {
            return ResponseEntity.ok(ApiResponse.error(400, "Failed to create bike: " + e.getMessage()));
        }
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<BicycleDto>>> getBikes(HttpServletRequest request) {
        try {
            Long userId = getUserIdFromToken(request);
            List<BicycleDto> bikes = bicycleService.getUserBikes(userId);
            return ResponseEntity.ok(ApiResponse.success(bikes));
        } catch (Exception e) {
            return ResponseEntity.ok(ApiResponse.error(401, "Unauthorized: " + e.getMessage()));
        }
    }

    @GetMapping("/{bikeId}")
    public ResponseEntity<ApiResponse<BicycleDto>> getBike(
            @PathVariable Long bikeId,
            HttpServletRequest request) {
        try {
            Long userId = getUserIdFromToken(request);
            BicycleDto bike = bicycleService.getBikeById(bikeId, userId);
            return ResponseEntity.ok(ApiResponse.success(bike));
        } catch (IllegalArgumentException e) {
            int code = e.getMessage().contains("Unauthorized") ? 403 : 404;
            return ResponseEntity.ok(ApiResponse.error(code, e.getMessage()));
        }
    }

    @PutMapping("/{bikeId}")
    public ResponseEntity<ApiResponse<BicycleDto>> updateBike(
            @PathVariable Long bikeId,
            @RequestBody BicycleDto bikeDto,
            HttpServletRequest request) {
        try {
            Long userId = getUserIdFromToken(request);
            BicycleDto result = bicycleService.updateBike(bikeId, userId, bikeDto);
            return ResponseEntity.ok(ApiResponse.success(result));
        } catch (IllegalArgumentException e) {
            int code = e.getMessage().contains("Unauthorized") ? 403 : 404;
            return ResponseEntity.ok(ApiResponse.error(code, e.getMessage()));
        }
    }

    @DeleteMapping("/{bikeId}")
    public ResponseEntity<ApiResponse<String>> deleteBike(
            @PathVariable Long bikeId,
            HttpServletRequest request) {
        try {
            Long userId = getUserIdFromToken(request);
            bicycleService.deleteBike(bikeId, userId);
            return ResponseEntity.ok(ApiResponse.success("Bike deleted successfully"));
        } catch (IllegalArgumentException e) {
            int code = e.getMessage().contains("Unauthorized") ? 403 : 404;
            return ResponseEntity.ok(ApiResponse.error(code, e.getMessage()));
        }
    }
}
