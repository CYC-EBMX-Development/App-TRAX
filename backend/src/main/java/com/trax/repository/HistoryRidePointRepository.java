package com.trax.repository;

import com.trax.model.HistoryRidePoint;
import org.springframework.data.jpa.repository.JpaRepository;

public interface HistoryRidePointRepository extends JpaRepository<HistoryRidePoint, Long> {
}
