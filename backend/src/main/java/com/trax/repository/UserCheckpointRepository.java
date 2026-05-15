package com.trax.repository;

import com.trax.model.UserCheckpoint;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserCheckpointRepository extends JpaRepository<UserCheckpoint, Long> {
    /** Active (non-soft-deleted) checkpoints for (user, trail). */
    @Query("SELECT c FROM UserCheckpoint c WHERE c.user.id = :userId AND c.trail.id = :trailId " +
           "AND c.deletedAt IS NULL ORDER BY c.sequenceIndex ASC")
    List<UserCheckpoint> findByUserIdAndTrailIdOrderBySequenceIndexAsc(
            @Param("userId") Long userId, @Param("trailId") Long trailId);

    @Query("SELECT COUNT(c) FROM UserCheckpoint c WHERE c.user.id = :userId AND c.trail.id = :trailId " +
           "AND c.deletedAt IS NULL")
    long countByUserIdAndTrailId(@Param("userId") Long userId, @Param("trailId") Long trailId);

    @Query("SELECT c FROM UserCheckpoint c WHERE c.id = :id AND c.user.id = :userId AND c.deletedAt IS NULL")
    Optional<UserCheckpoint> findByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);

    /** Count ALL checkpoints for a trail (incl. soft-deleted) — used to decide hard delete. */
    long countByTrailId(Long trailId);

    void deleteByTrailId(Long trailId);
}
