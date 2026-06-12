package com.trax.repository;

import com.trax.model.RidePoint;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface RidePointRepository extends JpaRepository<RidePoint, Long> {
    List<RidePoint> findByRideIdOrderByTimestampAsc(Long rideId);

        @Query("""
                        select p from RidePoint p
                        where p.ride.id = :rideId
                        order by
                            case when p.capturedAtMs is null then 1 else 0 end asc,
                            p.capturedAtMs asc,
                            p.timestamp asc,
                            p.id asc
                        """)
        List<RidePoint> findByRideIdOrderByCapturedAtMsAsc(@Param("rideId") Long rideId);

    List<RidePoint> findByRideId(Long rideId);
    void deleteByRideId(Long rideId);
    long countByRideId(Long rideId);

    /**
     * Dedup guard used by {@code LocationIngestService} so the same GPS fix
     * arriving via MQTT realtime AND BLE-backfill (or any other duplicated
     * transport) only produces one row per ride.
     */
    boolean existsByRideIdAndCapturedAtMs(Long rideId, Long capturedAtMs);
}
