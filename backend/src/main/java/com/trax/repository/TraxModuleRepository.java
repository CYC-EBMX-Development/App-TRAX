package com.trax.repository;

import com.trax.model.TraxModule;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface TraxModuleRepository extends JpaRepository<TraxModule, Long> {
    Optional<TraxModule> findBySerialNo(String serialNo);
}
