package com.trax.repository;

import com.trax.model.Trail;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface TrailRepository extends JpaRepository<Trail, Long> {
    List<Trail> findByDifficulty(String difficulty);
    List<Trail> findByDeletedFalse();
    List<Trail> findByCreatorIdAndDeletedFalse(Long creatorId);

    @Query("SELECT t FROM Trail t WHERE t.deleted = false AND (t.isPublic = true OR t.creatorId = :userId)")
    List<Trail> findVisibleTrails(@Param("userId") Long userId);
}
