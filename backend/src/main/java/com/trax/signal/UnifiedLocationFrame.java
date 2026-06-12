package com.trax.signal;

/**
 * Canonical location frame consumed by all business-layer code
 * (ride_points writers, lap detection, race shared pool, stats).
 *
 * <p>Business code MUST NOT inspect raw module NMEA / phone Position
 * structs — it only sees this record. The raw-to-unified translation
 * is the sole responsibility of an adapter in this package
 * ({@code ModuleNmeaAdapter}, {@code PhoneGpsAdapter}, ...).
 *
 * <p>Hard rule: {@link #capturedAtMs} is the real moment the GPS fix
 * happened (from NMEA UTC for module, from {@code Position.timestamp}
 * for phone). It is NOT the moment the frame reached the server.
 * Delayed delivery (BLE-backfill, MQTT reconnect) keeps the original
 * capturedAtMs so downstream ordering and ride-window matching stay
 * correct.
 */
public record UnifiedLocationFrame(
        long capturedAtMs,
        double latitude,
        double longitude,
        Double altitude,
        Double speedMps,
        Double headingDeg,
        Double hdop,
        SignalSource source,
        String sourceId
) {
    public UnifiedLocationFrame {
        if (capturedAtMs <= 0) {
            throw new IllegalArgumentException("capturedAtMs must be > 0; got " + capturedAtMs);
        }
        if (source == null) {
            throw new IllegalArgumentException("source must not be null");
        }
    }
}
