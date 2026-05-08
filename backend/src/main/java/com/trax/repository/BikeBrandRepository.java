package com.trax.repository;

import com.trax.model.BikeBrand;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BikeBrandRepository extends JpaRepository<BikeBrand, Long> {
}
