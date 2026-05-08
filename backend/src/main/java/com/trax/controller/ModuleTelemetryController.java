package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.ModuleTelemetryDto;
import com.trax.service.ModuleSimulatorService;
import com.trax.service.ModuleTelemetryService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/modules")
public class ModuleTelemetryController {
    private final ModuleTelemetryService telemetryService;
    private final ModuleSimulatorService simulatorService;

    public ModuleTelemetryController(ModuleTelemetryService telemetryService,
                                     ModuleSimulatorService simulatorService) {
        this.telemetryService = telemetryService;
        this.simulatorService = simulatorService;
    }

    @GetMapping("/{serialNo}/telemetry/latest")
    public ResponseEntity<ApiResponse<ModuleTelemetryDto>> getLatestTelemetry(
            @PathVariable String serialNo) {
        ModuleTelemetryDto dto = telemetryService.getLatestTelemetry(serialNo);
        return ResponseEntity.ok(ApiResponse.success(dto));
    }

    @PostMapping("/{serialNo}/telemetry")
    public ResponseEntity<ApiResponse<ModuleTelemetryDto>> recordTelemetry(
            @PathVariable String serialNo, @RequestBody ModuleTelemetryDto dto) {
        return ResponseEntity.ok(ApiResponse.success(
                telemetryService.recordTelemetry(serialNo, dto)));
    }

    @PostMapping("/simulate/start")
    public ResponseEntity<ApiResponse<String>> startSimulation(
            @RequestParam String serialNo,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude,
            @RequestParam(required = false) Long rideId) {
        simulatorService.startSimulation(serialNo, latitude, longitude, rideId);
        return ResponseEntity.ok(ApiResponse.success("Simulation started for " + serialNo));
    }

    @PostMapping("/simulate/pause")
    public ResponseEntity<ApiResponse<String>> pauseSimulation(@RequestParam String serialNo) {
        simulatorService.pauseSimulation(serialNo);
        return ResponseEntity.ok(ApiResponse.success("Simulation paused for " + serialNo));
    }

    @PostMapping("/simulate/resume")
    public ResponseEntity<ApiResponse<String>> resumeSimulation(@RequestParam String serialNo) {
        simulatorService.resumeSimulation(serialNo);
        return ResponseEntity.ok(ApiResponse.success("Simulation resumed for " + serialNo));
    }

    @PostMapping("/simulate/stop")
    public ResponseEntity<ApiResponse<String>> stopSimulation(@RequestParam String serialNo) {
        simulatorService.stopSimulation(serialNo);
        return ResponseEntity.ok(ApiResponse.success("Simulation stopped for " + serialNo));
    }
}
