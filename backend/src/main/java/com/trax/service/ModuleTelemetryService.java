package com.trax.service;

import com.trax.dto.ModuleTelemetryDto;
import com.trax.model.ModuleTelemetry;
import com.trax.model.TraxModule;
import com.trax.repository.ModuleTelemetryRepository;
import com.trax.repository.TraxModuleRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@Service
public class ModuleTelemetryService {
    private final ModuleTelemetryRepository telemetryRepository;
    private final TraxModuleRepository moduleRepository;

    public ModuleTelemetryService(ModuleTelemetryRepository telemetryRepository,
                                  TraxModuleRepository moduleRepository) {
        this.telemetryRepository = telemetryRepository;
        this.moduleRepository = moduleRepository;
    }

    public ModuleTelemetryDto recordTelemetry(String serialNo, ModuleTelemetryDto dto) {
        TraxModule module = moduleRepository.findBySerialNo(serialNo)
                .orElseThrow(() -> new IllegalArgumentException("Module not found: " + serialNo));

        ModuleTelemetry t = new ModuleTelemetry();
        t.setModule(module);
        t.setLatitude(dto.getLatitude());
        t.setLongitude(dto.getLongitude());
        t.setSpeed(dto.getSpeed());
        t.setBatteryPercent(dto.getBatteryPercent());
        t.setSignalStrength(dto.getSignalStrength());
        t.setTimestamp(LocalDateTime.now());
        telemetryRepository.save(t);

        dto.setSerialNo(serialNo);
        dto.setTimestamp(t.getTimestamp().toString());
        return dto;
    }

    public ModuleTelemetryDto getLatestTelemetry(String serialNo) {
        return telemetryRepository.findTopByModuleSerialNoOrderByTimestampDesc(serialNo)
                .map(t -> {
                    ModuleTelemetryDto dto = new ModuleTelemetryDto();
                    dto.setSerialNo(serialNo);
                    dto.setLatitude(t.getLatitude());
                    dto.setLongitude(t.getLongitude());
                    dto.setSpeed(t.getSpeed());
                    dto.setBatteryPercent(t.getBatteryPercent());
                    dto.setSignalStrength(t.getSignalStrength());
                    dto.setTimestamp(t.getTimestamp().toString());
                    return dto;
                }).orElse(null);
    }
}
