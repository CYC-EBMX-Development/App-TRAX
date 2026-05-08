package com.trax.repository;

import com.trax.model.RidePoint;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface RidePointRepository extends JpaRepository<RidePoint, Long> {
    List<RidePoint> findByRideIdOrderByTimestampAsc(Long rideId);
    List<RidePoint> findByRideId(Long rideId);
    void deleteByRideId(Long rideId);
    long countByRideId(Long rideId);
}
