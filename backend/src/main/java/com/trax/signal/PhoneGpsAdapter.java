package com.trax.signal;

import com.trax.dto.RidePointDto;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;

/**
 * Translates a phone-side {@link RidePointDto} (uploaded by App through
 * {@code POST /api/rides/{id}/points}) into the canonical
 * {@link UnifiedLocationFrame}.
 *
 * <p>The DTO's {@code timestamp} field is the {@code Position.timestamp}
 * the Flutter Geolocator plugin captured at the moment of the GPS fix.
 * Accepted formats: ISO-8601 instant ({@code 2026-06-03T08:21:45.123Z})
 * and local-dateTime without offset ({@code 2026-06-03T16:21:45.123}).
 * Falls back to "now" only as a last resort and the caller is expected
 * to monitor that metric separately.
 */
public final class PhoneGpsAdapter {

    private PhoneGpsAdapter() {}

    public static UnifiedLocationFrame fromDto(RidePointDto dto, String deviceId) {
        if (dto == null) return null;
        long captured = parseToMs(dto.getTimestamp());
        return new UnifiedLocationFrame(
                captured,
                dto.getLatitude(),
                dto.getLongitude(),
                dto.getAltitude(),
                dto.getSpeed(),
                null,
                null,
                SignalSource.PHONE,
                deviceId
        );
    }

    /**
     * @return epoch millis, never {@code <= 0}. Falls back to server clock
     *         when the DTO timestamp is missing or unparseable.
     */
    static long parseToMs(String raw) {
        if (raw != null && !raw.isBlank()) {
            try {
                return Instant.parse(raw).toEpochMilli();
            } catch (DateTimeParseException ignore) {
                // fall through
            }
            try {
                return LocalDateTime.parse(raw)
                        .atZone(ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli();
            } catch (DateTimeParseException ignore) {
                // fall through
            }
        }
        return System.currentTimeMillis();
    }
}
