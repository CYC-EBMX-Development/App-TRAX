package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.TraxModuleDto;
import com.trax.model.BikeModel;
import com.trax.model.TraxModule;
import com.trax.repository.TraxModuleRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/trax-modules")
public class TraxModuleController {
    private final TraxModuleRepository traxModuleRepository;

    public TraxModuleController(TraxModuleRepository traxModuleRepository) {
        this.traxModuleRepository = traxModuleRepository;
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
