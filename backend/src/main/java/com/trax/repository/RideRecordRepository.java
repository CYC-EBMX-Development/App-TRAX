package com.trax.repository;

import com.trax.model.RideRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface RideRecordRepository extends JpaRepository<RideRecord, Long> {
    List<RideRecord> findByUserIdOrderByStartTimeDesc(Long userId);
    Optional<RideRecord> findFirstByUserIdAndStatusInOrderByStartTimeDesc(Long userId, List<String> statuses);
    List<RideRecord> findByBicycleId(Long bicycleId);
    long countByTrailId(Long trailId);

    /**
     * Returns rides for this bike whose {@code [startTime, endTime]} window
     * covers the supplied capture moment. {@code endTime is null} means the
     * ride is still active. Used by {@code LocationIngestService} to attach
     * both live and delayed (BLE-backfill / MQTT-reconnect) GPS fixes to
     * the correct ride.
     *
     * <p>Ordered most-recent-first so the active ride wins over any
     * historical ride that happens to have an overlapping window.
     */
    @Query("select r from RideRecord r where r.bicycle.id = :bikeId " +
            "and r.startTime <= :capturedAt " +
            "and (r.endTime is null or r.endTime >= :capturedAt) " +
            "order by r.startTime desc")
    List<RideRecord> findRideCoveringTime(@Param("bikeId") Long bikeId,
                                          @Param("capturedAt") LocalDateTime capturedAt);
}
