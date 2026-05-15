package com.trax.repository;

import com.trax.model.Race;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface RaceRepository extends JpaRepository<Race, Long> {

    Optional<Race> findByJoinCode(String joinCode);

    /** Find an unstarted race (waiting/preparing) with the given join code. */
    @Query("SELECT r FROM Race r WHERE r.joinCode = :code AND r.status IN ('waiting','preparing')")
    Optional<Race> findUnstartedByJoinCode(@Param("code") String code);

    /** Existence check for unstarted-event uniqueness when generating codes. */
    @Query("SELECT COUNT(r) > 0 FROM Race r WHERE r.joinCode = :code AND r.status IN ('waiting','preparing')")
    boolean existsUnstartedByJoinCode(@Param("code") String code);

    /** Public races the user has NOT joined/observed, in waiting status */
    @Query("SELECT r FROM Race r WHERE r.isPublic = true AND r.status = 'waiting' " +
           "AND r.id NOT IN (SELECT rp.race.id FROM RaceParticipant rp WHERE rp.user.id = :userId)")
    List<Race> findPublicRacesNotJoinedByUser(@Param("userId") Long userId);

    /** All public races (for observe listing) */
    @Query("SELECT r FROM Race r WHERE r.isPublic = true AND r.status IN ('waiting','preparing','in_progress') " +
           "AND r.id NOT IN (SELECT rp.race.id FROM RaceParticipant rp WHERE rp.user.id = :userId)")
    List<Race> findPublicRacesForObserver(@Param("userId") Long userId);

    /** Upcoming + in-progress events for a user (hosted or joined) */
    @Query("SELECT r FROM Race r WHERE r.id IN " +
           "(SELECT rp.race.id FROM RaceParticipant rp WHERE rp.user.id = :userId) " +
           "AND r.status IN ('waiting','preparing','in_progress') ORDER BY r.scheduledTime ASC")
    List<Race> findUpcomingByUser(@Param("userId") Long userId);

    /** All events for a user, paginated */
    @Query("SELECT r FROM Race r WHERE r.id IN " +
           "(SELECT rp.race.id FROM RaceParticipant rp WHERE rp.user.id = :userId) " +
           "ORDER BY r.createdAt DESC")
    Page<Race> findAllByUser(@Param("userId") Long userId, Pageable pageable);

    long countByTrailId(Long trailId);
}
