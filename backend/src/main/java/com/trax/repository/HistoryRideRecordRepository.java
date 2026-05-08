package com.trax.repository;

import com.trax.model.HistoryRideRecord;
import org.springframework.data.jpa.repository.JpaRepository;

public interface HistoryRideRecordRepository extends JpaRepository<HistoryRideRecord, Long> {
}
