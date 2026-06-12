package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.TraxModuleDto;
import com.trax.model.BikeModel;
import com.trax.model.TraxModule;
import com.trax.repository.BicycleRepository;
import com.trax.repository.TraxModuleRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/trax-modules")
public class TraxModuleController {
    private final TraxModuleRepository traxModuleRepository;
    private final BicycleRepository bicycleRepository;

    public TraxModuleController(TraxModuleRepository traxModuleRepository,
                                BicycleRepository bicycleRepository) {
        this.traxModuleRepository = traxModuleRepository;
        this.bicycleRepository = bicycleRepository;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<TraxModuleDto>>> getAllModules() {
        List<TraxModuleDto> dtos = traxModuleRepository.findAll()
                .stream()
                .map(this::toDto)
                .toList();
        return ResponseEntity.ok(ApiResponse.success(dtos));
    }

    @GetMapping("/{serialNo}")
    public ResponseEntity<ApiResponse<TraxModuleDto>> getBySerialNo(@PathVariable String serialNo) {
        return traxModuleRepository.findBySerialNo(serialNo)
                .map(m -> ResponseEntity.ok(ApiResponse.success(toDto(m))))
                .orElse(ResponseEntity.ok(ApiResponse.error(404, "Module not found")));
    }

    /**
     * Scan-time helper: given a list of serials surfaced by BLE, return the
     * subset that is already bound to a bicycle (so the UI can render a lock
     * badge and prevent rebinding). Checks {@code bicycles.trax_serial_number}
     * — the real ownership boundary — rather than the registry-only
     * {@code trax_module.bound} flag, which is only set when the module was
     * pre-registered.
     *
     * <p>Request: {@code {"serials": ["A", "B"]}}.
     * Response: {@code {"bound": ["A"]}}.
     */
    @PostMapping("/check-bound")
    public ResponseEntity<ApiResponse<Map<String, List<String>>>> checkBound(
            @RequestBody Map<String, List<String>> body) {
        List<String> serials = body == null ? null : body.get("serials");
        if (serials == null || serials.isEmpty()) {
            return ResponseEntity.ok(ApiResponse.success(
                    Map.of("bound", Collections.emptyList())));
        }
        // De-dup while preserving order for caller debug-friendliness.
        Set<String> unique = new java.util.LinkedHashSet<>(serials);
        List<String> bound = bicycleRepository.findBoundSerials(unique);
        return ResponseEntity.ok(ApiResponse.success(Map.of("bound", bound)));
    }

    private TraxModuleDto toDto(TraxModule module) {
        TraxModuleDto dto = new TraxModuleDto();
        dto.setSerialNo(module.getSerialNo());
        dto.setName(module.getName());
        dto.setBound(module.isBound());

        BikeModel model = module.getModel();
        if (model != null) {
            dto.setMotor(model.getMotorType());
            dto.setController(model.getController());
            dto.setBattery(model.getBatteryType());
            dto.setMotorCertified(true);
            dto.setControllerCertified(model.getController() != null);
            dto.setBatteryCertified(true);
            dto.setModelBrand(model.getBrand().getName());
            dto.setModelName(model.getModelName());
        }
        return dto;
    }
}
