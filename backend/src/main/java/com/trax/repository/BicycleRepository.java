package com.trax.repository;

import com.trax.model.Bicycle;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository
public interface BicycleRepository extends JpaRepository<Bicycle, Long> {
    List<Bicycle> findByOwnerIdOrderByCreatedAtDesc(Long ownerId);

    /**
     * Used by owner-auth checks on telemetry endpoints / WS handshake, and by
     * the bind-time uniqueness guard in {@code BicycleService}.
     *
     * <p>Returns a list (not Optional) because legacy data may contain the same
     * serial on more than one row. Callers must filter to the caller's
     * {@code ownerId} for auth checks and reject any duplicate at bind time.
     */
    List<Bicycle> findByTraxSerialNumber(String traxSerialNumber);

    /**
     * Returns the subset of the supplied serials that are currently bound to a
     * bicycle (any owner). Used by the scan-time "already bound" badge.
     */
    @Query("select distinct b.traxSerialNumber from Bicycle b " +
            "where b.traxSerialNumber in :serials")
    List<String> findBoundSerials(@Param("serials") Collection<String> serials);
}
