package com.trax.service;

import com.trax.dto.BikeBrandDto;
import com.trax.dto.BikeModelDto;
import com.trax.model.BikeBrand;
import com.trax.model.BikeModel;
import com.trax.repository.BikeBrandRepository;
import com.trax.repository.BikeModelRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class BikeModelService {
    private final BikeBrandRepository bikeBrandRepository;
    private final BikeModelRepository bikeModelRepository;

    public BikeModelService(BikeBrandRepository bikeBrandRepository, BikeModelRepository bikeModelRepository) {
        this.bikeBrandRepository = bikeBrandRepository;
        this.bikeModelRepository = bikeModelRepository;
    }

    public List<BikeBrandDto> getAllBrands() {
        return bikeBrandRepository.findAll()
                .stream()
                .map(this::toBrandDto)
                .collect(Collectors.toList());
    }

    public List<BikeModelDto> getModelsByBrand(Long brandId) {
        return bikeModelRepository.findByBrandId(brandId)
                .stream()
                .map(this::toModelDto)
                .collect(Collectors.toList());
    }

    private BikeBrandDto toBrandDto(BikeBrand brand) {
        return new BikeBrandDto(brand.getId(), brand.getName(), brand.getImageUrl());
    }

    private BikeModelDto toModelDto(BikeModel model) {
        BikeModelDto dto = new BikeModelDto();
        dto.setId(model.getId());
        dto.setModelName(model.getModelName());
        dto.setMotorType(model.getMotorType());
        dto.setController(model.getController());
        dto.setImageUrl(model.getImageUrl());
        if (model.getBrand() != null) {
            dto.setBrandName(model.getBrand().getName());
        }
        dto.setMotorPeakPowerW(model.getMotorPeakPowerW());
        dto.setMotorTorqueNm(model.getMotorTorqueNm());
        dto.setBatteryType(model.getBatteryType());
        dto.setBatteryVoltage(model.getBatteryVoltage());
        dto.setBatteryCapacityWh(model.getBatteryCapacityWh());
        return dto;
    }
}
