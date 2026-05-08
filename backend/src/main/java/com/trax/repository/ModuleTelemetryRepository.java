package com.trax.repository;

import com.trax.model.ModuleTelemetry;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface ModuleTelemetryRepository extends JpaRepository<ModuleTelemetry, Long> {
    Optional<ModuleTelemetry> findTopByModuleSerialNoOrderByTimestampDesc(String serialNo);
}
