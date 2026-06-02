package com.trax.util;

import com.trax.model.User;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

import static org.assertj.core.api.Assertions.assertThat;

class AvatarUrlsTest {

    @Test
    void nullUserReturnsNull() {
        assertThat(AvatarUrls.versioned((User) null)).isNull();
    }

    @Test
    void emptyOrNullUrlReturnsNull() {
        assertThat(AvatarUrls.versioned(null, LocalDateTime.now())).isNull();
        assertThat(AvatarUrls.versioned("", LocalDateTime.now())).isNull();
    }

    @Test
    void appendsQueryWhenNoExistingQuery() {
        LocalDateTime t = LocalDateTime.of(2026, 5, 18, 0, 0).truncatedTo(ChronoUnit.SECONDS);
        String out = AvatarUrls.versioned("/avatars/1.jpg", t);
        long expected = t.toEpochSecond(ZoneOffset.UTC);
        assertThat(out).isEqualTo("/avatars/1.jpg?v=" + expected);
    }

    @Test
    void appendsAmpersandWhenUrlAlreadyHasQuery() {
        LocalDateTime t = LocalDateTime.of(2026, 5, 18, 0, 0);
        String out = AvatarUrls.versioned("/avatars/1.jpg?size=200", t);
        assertThat(out).startsWith("/avatars/1.jpg?size=200&v=");
    }

    @Test
    void idempotentWhenAlreadyVersioned() {
        String already = "/avatars/1.jpg?v=12345";
        assertThat(AvatarUrls.versioned(already, LocalDateTime.now())).isEqualTo(already);
    }

    @Test
    void nullUpdatedAtUsesZeroVersion() {
        assertThat(AvatarUrls.versioned("/x.png", null)).isEqualTo("/x.png?v=0");
    }
}
