package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.BikeBrandDto;
import com.trax.dto.BikeModelDto;
import com.trax.service.BikeModelService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/bike-models")
public class BikeModelController {
    private final BikeModelService bikeModelService;

    public BikeModelController(BikeModelService bikeModelService) {
        this.bikeModelService = bikeModelService;
    }

    @GetMapping("/brands")
    public ResponseEntity<ApiResponse<List<BikeBrandDto>>> getAllBrands() {
        List<BikeBrandDto> brands = bikeModelService.getAllBrands();
        return ResponseEntity.ok(ApiResponse.success(brands));
    }

    @GetMapping("/brands/{brandId}/models")
    public ResponseEntity<ApiResponse<List<BikeModelDto>>> getModelsByBrand(@PathVariable Long brandId) {
        List<BikeModelDto> models = bikeModelService.getModelsByBrand(brandId);
        return ResponseEntity.ok(ApiResponse.success(models));
    }
}
