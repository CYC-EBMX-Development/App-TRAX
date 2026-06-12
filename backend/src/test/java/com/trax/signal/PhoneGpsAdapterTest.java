package com.trax.signal;

import com.trax.dto.RidePointDto;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;

import static org.assertj.core.api.Assertions.assertThat;

class PhoneGpsAdapterTest {

    private static RidePointDto dto(String ts) {
        RidePointDto d = new RidePointDto();
        d.setLatitude(22.5);
        d.setLongitude(113.9);
        d.setSpeed(8.0);
        d.setAltitude(15.0);
        d.setTimestamp(ts);
        return d;
    }

    @Test
    void returnsNullWhenDtoIsNull() {
        assertThat(PhoneGpsAdapter.fromDto(null, "phone-A")).isNull();
    }

    @Test
    void parsesIso8601Instant() {
        String iso = "2026-06-03T08:21:45.123Z";
        UnifiedLocationFrame uf = PhoneGpsAdapter.fromDto(dto(iso), "phone-A");

        assertThat(uf).isNotNull();
        assertThat(uf.capturedAtMs()).isEqualTo(Instant.parse(iso).toEpochMilli());
        assertThat(uf.source()).isEqualTo(SignalSource.PHONE);
        assertThat(uf.sourceId()).isEqualTo("phone-A");
        assertThat(uf.latitude()).isEqualTo(22.5);
        assertThat(uf.longitude()).isEqualTo(113.9);
        assertThat(uf.speedMps()).isEqualTo(8.0);
        assertThat(uf.altitude()).isEqualTo(15.0);
    }

    @Test
    void parsesLocalDateTimeWithoutOffset() {
        String local = "2026-06-03T16:21:45.123";
        long expected = LocalDateTime.parse(local).atZone(ZoneId.systemDefault())
                .toInstant().toEpochMilli();

        UnifiedLocationFrame uf = PhoneGpsAdapter.fromDto(dto(local), null);

        assertThat(uf.capturedAtMs()).isEqualTo(expected);
    }

    @Test
    void fallsBackToNowWhenTimestampMissingOrUnparseable() {
        long before = System.currentTimeMillis();
        UnifiedLocationFrame uf1 = PhoneGpsAdapter.fromDto(dto(null), null);
        UnifiedLocationFrame uf2 = PhoneGpsAdapter.fromDto(dto("garbage"), null);
        long after = System.currentTimeMillis();

        assertThat(uf1.capturedAtMs()).isBetween(before, after);
        assertThat(uf2.capturedAtMs()).isBetween(before, after);
    }
}
