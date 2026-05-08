package com.trax.repository;

import com.trax.model.BikeModel;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface BikeModelRepository extends JpaRepository<BikeModel, Long> {
    List<BikeModel> findByBrandId(Long brandId);
    Optional<BikeModel> findByModelNameAndBrand_Name(String modelName, String brandName);
}
