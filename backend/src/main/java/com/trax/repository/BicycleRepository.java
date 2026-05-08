package com.trax.repository;

import com.trax.model.Bicycle;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface BicycleRepository extends JpaRepository<Bicycle, Long> {
    List<Bicycle> findByOwnerIdOrderByCreatedAtDesc(Long ownerId);
}
