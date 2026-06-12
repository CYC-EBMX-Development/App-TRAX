package com.trax.repository;

import com.trax.model.ModuleTelemetry;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.Optional;

public interface ModuleTelemetryRepository extends JpaRepository<ModuleTelemetry, Long> {
    Optional<ModuleTelemetry> findTopByModuleSerialNoOrderByTimestampDesc(String serialNo);

    /** Used to hide previous-owner data after a re-bind — caller passes module.boundAt. */
    Optional<ModuleTelemetry> findTopByModuleSerialNoAndTimestampGreaterThanEqualOrderByTimestampDesc(
            String serialNo, LocalDateTime since);

    boolean existsByModuleIdAndTimestampMillis(Long moduleId, Long timestampMillis);
}
