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

    /**
     * Bounding-box scan for trails near a point. Cheap (no trig in SQL) —
     * callers should refine by exact haversine distance in Java and apply
     * a final limit. Returns at most {@code maxRows} rows.
     */
    @Query(value =
            "SELECT * FROM trails t " +
            "WHERE t.deleted = false " +
            "  AND (t.is_public = true OR t.creator_id = :userId) " +
            "  AND t.start_latitude BETWEEN :minLat AND :maxLat " +
            "  AND t.start_longitude BETWEEN :minLng AND :maxLng " +
            "LIMIT :maxRows",
            nativeQuery = true)
    List<Trail> findVisibleInBoundingBox(@Param("userId") Long userId,
                                         @Param("minLat") double minLat,
                                         @Param("maxLat") double maxLat,
                                         @Param("minLng") double minLng,
                                         @Param("maxLng") double maxLng,
                                         @Param("maxRows") int maxRows);
}
