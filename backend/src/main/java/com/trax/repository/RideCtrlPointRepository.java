package com.trax.repository;

import com.trax.model.RideCtrlPoint;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface RideCtrlPointRepository extends JpaRepository<RideCtrlPoint, Long> {

    /** Dedup guard: at most one ctrl row per ride per capturedAtMs. */
    boolean existsByRideIdAndCapturedAtMs(Long rideId, Long capturedAtMs);

    @Query("""
            select p from RideCtrlPoint p
            where p.ride.id = :rideId
            order by
                case when p.capturedAtMs is null then 1 else 0 end asc,
                p.capturedAtMs asc,
                p.timestamp asc,
                p.id asc
            """)
    List<RideCtrlPoint> findByRideIdOrderByCapturedAtMsAsc(@Param("rideId") Long rideId);

    void deleteByRideId(Long rideId);
    long countByRideId(Long rideId);
}
