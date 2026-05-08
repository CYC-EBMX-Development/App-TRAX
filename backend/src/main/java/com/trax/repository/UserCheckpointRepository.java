package com.trax.repository;

import com.trax.model.UserCheckpoint;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserCheckpointRepository extends JpaRepository<UserCheckpoint, Long> {
    List<UserCheckpoint> findByUserIdAndTrailIdOrderBySequenceIndexAsc(Long userId, Long trailId);
    long countByUserIdAndTrailId(Long userId, Long trailId);
    Optional<UserCheckpoint> findByIdAndUserId(Long id, Long userId);
}
