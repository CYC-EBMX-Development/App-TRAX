package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.ModuleTelemetryDto;
import com.trax.repository.BicycleRepository;
import com.trax.repository.UserRepository;
import com.trax.security.JwtUtil;
import com.trax.service.ModuleTelemetryService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/modules")
public class ModuleTelemetryController {
    private final ModuleTelemetryService telemetryService;
    private final JwtUtil jwtUtil;
    private final UserRepository userRepository;
    private final BicycleRepository bicycleRepository;

    public ModuleTelemetryController(ModuleTelemetryService telemetryService,
                                     JwtUtil jwtUtil,
                                     UserRepository userRepository,
                                     BicycleRepository bicycleRepository) {
        this.telemetryService = telemetryService;
        this.jwtUtil = jwtUtil;
        this.userRepository = userRepository;
        this.bicycleRepository = bicycleRepository;
    }

    /**
     * Verifies the JWT-authenticated caller is the owner of the bicycle
     * currently bound to {@code serialNo}. Returns the bike for callers
     * who want it, throws ResponseStatusException-equivalent for non-owners.
     */
    private void requireOwner(HttpServletRequest request, String serialNo) {
        String authHeader = request.getHeader("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "Missing token");
        }
        String token = authHeader.substring(7);
        if (!jwtUtil.validateToken(token)) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "Invalid token");
        }
        Long callerId = userRepository.findByEmail(jwtUtil.extractEmail(token))
                .map(u -> u.getId()).orElse(null);
        if (callerId == null) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "Unknown user");
        }
        boolean owned = bicycleRepository.findByTraxSerialNumber(serialNo).stream()
                .anyMatch(b -> b.getOwner() != null && callerId.equals(b.getOwner().getId()));
        if (!owned) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Not owner of module");
        }
    }

    @GetMapping("/{serialNo}/telemetry/latest")
    public ResponseEntity<ApiResponse<ModuleTelemetryDto>> getLatestTelemetry(
            @PathVariable String serialNo, HttpServletRequest request) {
        requireOwner(request, serialNo);
        ModuleTelemetryDto dto = telemetryService.getLatestTelemetry(serialNo);
        return ResponseEntity.ok(ApiResponse.success(dto));
    }

    @PostMapping("/{serialNo}/telemetry")
    public ResponseEntity<ApiResponse<ModuleTelemetryDto>> recordTelemetry(
            @PathVariable String serialNo, @RequestBody ModuleTelemetryDto dto,
            HttpServletRequest request) {
        requireOwner(request, serialNo);
        return ResponseEntity.ok(ApiResponse.success(
                telemetryService.recordTelemetry(serialNo, dto)));
    }

    /**
     * Bulk-ingest NMEA $PCYCGPS lines captured from a module via the App's
     * BLE relay (offline-module path).  Idempotent: server dedups by
     * (module_id, ts_millis), so the App may safely retry on failure.
     *
     * Body: {@code { "nmea": ["$PCYCGPS,...*XX", "$PCYCGPS,...*XX"] }}
     */
    @PostMapping("/{serialNo}/telemetry/batch")
    public ResponseEntity<ApiResponse<Map<String, Integer>>> recordBatch(
            @PathVariable String serialNo,
            @RequestBody BatchRequest body,
            HttpServletRequest request) {
        requireOwner(request, serialNo);
        int kept = telemetryService.recordBatchNmea(serialNo, body.nmea);
        return ResponseEntity.ok(ApiResponse.success(Map.of(
                "inserted", kept,
                "submitted", body.nmea == null ? 0 : body.nmea.size())));
    }

    public static class BatchRequest {
        public List<String> nmea;
    }
}
