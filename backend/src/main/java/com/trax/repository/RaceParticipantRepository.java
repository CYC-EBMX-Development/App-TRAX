package com.trax.repository;

import com.trax.model.RaceParticipant;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface RaceParticipantRepository extends JpaRepository<RaceParticipant, Long> {

    List<RaceParticipant> findByRaceId(Long raceId);

    List<RaceParticipant> findByRaceIdAndRole(Long raceId, String role);

    List<RaceParticipant> findByRaceIdAndRoleIn(Long raceId, List<String> roles);

    Optional<RaceParticipant> findByRaceIdAndUserId(Long raceId, Long userId);

    boolean existsByRaceIdAndUserId(Long raceId, Long userId);

    /** Count riders (not observers) in a race */
    long countByRaceIdAndRoleIn(Long raceId, List<String> roles);

    /** Find participants by ride record (for cleanup on ride deletion) */
    List<RaceParticipant> findByRideId(Long rideId);
}
