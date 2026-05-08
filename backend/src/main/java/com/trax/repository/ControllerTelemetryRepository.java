package com.trax.repository;

import com.trax.model.ControllerTelemetry;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ControllerTelemetryRepository extends JpaRepository<ControllerTelemetry, Long> {
    List<ControllerTelemetry> findByRideIdOrderByTimestampAsc(Long rideId);
    long countByRideId(Long rideId);
    void deleteByRideId(Long rideId);
}
