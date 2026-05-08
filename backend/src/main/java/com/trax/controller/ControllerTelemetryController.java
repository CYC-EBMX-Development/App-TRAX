package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.model.ControllerTelemetry;
import com.trax.repository.ControllerTelemetryRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * REST endpoints for the per-second motor-controller telemetry stream.
 *
 * <p>Backed by the {@code controller_telemetry} table. Every row is the
 * 26-channel packet the TRAX module reads off the e-motorcycle's controller
 * bus and uploads at 1 Hz, time-aligned with the matching ride point.
 */
@RestController
@RequestMapping("/api/rides/{rideId}/controller-telemetry")
public class ControllerTelemetryController {

    private final ControllerTelemetryRepository repo;

    public ControllerTelemetryController(ControllerTelemetryRepository repo) {
        this.repo = repo;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<Map<String, Object>>>> list(
            @PathVariable Long rideId) {
        List<ControllerTelemetry> rows = repo.findByRideIdOrderByTimestampAsc(rideId);
        List<Map<String, Object>> out = rows.stream().map(this::toMap).toList();
        return ResponseEntity.ok(ApiResponse.success(out));
    }

    @GetMapping("/count")
    public ResponseEntity<ApiResponse<Long>> count(@PathVariable Long rideId) {
        return ResponseEntity.ok(ApiResponse.success(repo.countByRideId(rideId)));
    }

    private Map<String, Object> toMap(ControllerTelemetry t) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", t.getId());
        m.put("timestamp", t.getTimestamp() != null ? t.getTimestamp().toString() : null);
        m.put("ridePointId", t.getRidePoint() != null ? t.getRidePoint().getId() : null);
        m.put("fetTempC", t.getFetTempC());
        m.put("motorTempC", t.getMotorTempC());
        m.put("avgMotorCurrentA", t.getAvgMotorCurrentA());
        m.put("avgInputCurrentA", t.getAvgInputCurrentA());
        m.put("avgIdA", t.getAvgIdA());
        m.put("avgIqA", t.getAvgIqA());
        m.put("dutyCycle", t.getDutyCycle());
        m.put("motorRpm", t.getMotorRpm());
        m.put("inputVoltageV", t.getInputVoltageV());
        m.put("ampHoursAh", t.getAmpHoursAh());
        m.put("tripTimeS", t.getTripTimeS());
        m.put("wattHoursWh", t.getWattHoursWh());
        m.put("encoderSinV", t.getEncoderSinV());
        m.put("throttleAdcV", t.getThrottleAdcV());
        m.put("regenAdcV", t.getRegenAdcV());
        m.put("faultCode", t.getFaultCode());
        m.put("digitalInputState", t.getDigitalInputState());
        m.put("controllerId", t.getControllerId());
        m.put("ntcMosTempA", t.getNtcMosTempA());
        m.put("ntcMosTempB", t.getNtcMosTempB());
        m.put("ntcMosTempC", t.getNtcMosTempC());
        m.put("avgVdV", t.getAvgVdV());
        m.put("avgVqV", t.getAvgVqV());
        m.put("odometerM", t.getOdometerM());
        m.put("encoderCosV", t.getEncoderCosV());
        m.put("speedKmh", t.getSpeedKmh());
        m.put("rsMode", t.getRsMode());
        m.put("assistLevel", t.getAssistLevel());
        return m;
    }
}
