package com.trax.repository;

import com.trax.model.RideRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface RideRecordRepository extends JpaRepository<RideRecord, Long> {
    List<RideRecord> findByUserIdOrderByStartTimeDesc(Long userId);
    Optional<RideRecord> findFirstByUserIdAndStatusInOrderByStartTimeDesc(Long userId, List<String> statuses);
    List<RideRecord> findByBicycleId(Long bicycleId);
}
