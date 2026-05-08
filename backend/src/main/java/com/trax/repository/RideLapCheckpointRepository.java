package com.trax.repository;

import com.trax.model.RideLapCheckpoint;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface RideLapCheckpointRepository extends JpaRepository<RideLapCheckpoint, Long> {
    List<RideLapCheckpoint> findByLapIdOrderBySequenceIndexAsc(Long lapId);
    List<RideLapCheckpoint> findByLapIdInOrderByLapIdAscSequenceIndexAsc(List<Long> lapIds);
}
