package com.trax.repository;

import com.trax.model.TrailPoint;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface TrailPointRepository extends JpaRepository<TrailPoint, Long> {
    List<TrailPoint> findByTrailIdOrderBySequenceIndexAsc(Long trailId);
    void deleteByTrailId(Long trailId);
}
