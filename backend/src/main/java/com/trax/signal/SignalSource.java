package com.trax.signal;

/**
 * Where a {@link UnifiedLocationFrame} originated from.
 *
 * <p>Note: BLE-backfill is NOT a separate source — it is the MODULE source
 * delivered through a delayed transport (phone acts as a relay pipe only).
 * The same rule applies to MQTT-backfill when a module reconnects after a
 * network outage and flushes its local NMEA cache. Both land here with
 * {@link #MODULE}.
 */
public enum SignalSource {
    /** Data captured by an on-vehicle TRAX module (via MQTT realtime, MQTT-backfill, or BLE-relay). */
    MODULE,
    /** Data captured by the rider's phone GPS (uploaded via HTTP batch). */
    PHONE
}
