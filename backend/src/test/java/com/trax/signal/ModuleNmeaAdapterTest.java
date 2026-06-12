package com.trax.signal;

import com.cyc.iot.common.model.GpsFrame;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class ModuleNmeaAdapterTest {

    private static GpsFrame frame(Instant ts) {
        GpsFrame f = new GpsFrame();
        f.setDeviceId("vesc_express");
        f.setTs(ts);
        f.setLat(31.0);
        f.setLon(121.0);
        f.setAlt(10.5);
        f.setSpeed(5.0);
        f.setCourse(180.0);
        f.setHdop(1.2);
        return f;
    }

    @Test
    void returnsNullWhenFrameIsNull() {
        assertThat(ModuleNmeaAdapter.fromGpsFrame(null)).isNull();
    }

    @Test
    void returnsNullWhenTimestampMissing() {
        GpsFrame f = frame(null);
        assertThat(ModuleNmeaAdapter.fromGpsFrame(f)).isNull();
    }

    @Test
    void mapsAllFieldsAndMarksSourceModule() {
        Instant ts = Instant.parse("2026-06-03T01:23:45.678Z");
        UnifiedLocationFrame uf = ModuleNmeaAdapter.fromGpsFrame(frame(ts));

        assertThat(uf).isNotNull();
        assertThat(uf.capturedAtMs()).isEqualTo(ts.toEpochMilli());
        assertThat(uf.latitude()).isEqualTo(31.0);
        assertThat(uf.longitude()).isEqualTo(121.0);
        assertThat(uf.altitude()).isEqualTo(10.5);
        assertThat(uf.speedMps()).isEqualTo(5.0);
        assertThat(uf.headingDeg()).isEqualTo(180.0);
        assertThat(uf.hdop()).isEqualTo(1.2);
        assertThat(uf.source()).isEqualTo(SignalSource.MODULE);
        assertThat(uf.sourceId()).isEqualTo("vesc_express");
    }

    @Test
    void nanOpticalFieldsBecomeNull() {
        GpsFrame f = frame(Instant.parse("2026-06-03T01:00:00Z"));
        f.setAlt(Double.NaN);
        f.setSpeed(Double.NaN);
        f.setCourse(Double.NaN);
        f.setHdop(Double.NaN);

        UnifiedLocationFrame uf = ModuleNmeaAdapter.fromGpsFrame(f);

        assertThat(uf).isNotNull();
        assertThat(uf.altitude()).isNull();
        assertThat(uf.speedMps()).isNull();
        assertThat(uf.headingDeg()).isNull();
        assertThat(uf.hdop()).isNull();
    }
}
