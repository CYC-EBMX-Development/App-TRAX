package com.trax.signal;

import com.cyc.iot.common.model.GpsFrame;

/**
 * Translates a vesc-iot {@link GpsFrame} (decoded from $PCYCGPS / $PCYCPOS)
 * into the canonical {@link UnifiedLocationFrame}.
 *
 * <p>Rejects frames without a real NMEA UTC timestamp — we never fall back
 * to {@code System.currentTimeMillis()} for module data, because that would
 * corrupt the timeline for delayed deliveries (BLE-backfill, MQTT reconnect).
 */
public final class ModuleNmeaAdapter {

    private ModuleNmeaAdapter() {}

    /** @return null if the frame has no usable timestamp; never throws. */
    public static UnifiedLocationFrame fromGpsFrame(GpsFrame f) {
        if (f == null || f.getTs() == null) return null;
        long captured = f.getTs().toEpochMilli();
        if (captured <= 0) return null;

        return new UnifiedLocationFrame(
                captured,
                f.getLat(),
                f.getLon(),
                Double.isNaN(f.getAlt())    ? null : f.getAlt(),
                Double.isNaN(f.getSpeed())  ? null : f.getSpeed(),
                Double.isNaN(f.getCourse()) ? null : f.getCourse(),
                Double.isNaN(f.getHdop())   ? null : f.getHdop(),
                SignalSource.MODULE,
                f.getDeviceId()
        );
    }
}
