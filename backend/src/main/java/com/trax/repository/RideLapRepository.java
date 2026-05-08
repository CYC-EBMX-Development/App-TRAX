package com.trax.repository;

import com.trax.model.RideLap;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface RideLapRepository extends JpaRepository<RideLap, Long> {
    List<RideLap> findByRideIdOrderByLapNumberAsc(Long rideId);
    void deleteByRideId(Long rideId);
}
