package com.trax.util;

import com.trax.model.User;

import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * Helper for building cache-busting avatar URLs.
 *
 * <p>Clients (Flutter {@code NetworkImage}, Google Maps marker bitmaps,
 * browsers, CDNs) all cache images keyed by the full URL. When a user
 * uploads a new avatar but the storage path stays the same
 * (e.g. {@code /avatars/123.jpg}), every cache will keep serving the
 * stale image.
 *
 * <p>This helper appends {@code ?v=<epochSecondsOfUpdatedAt>} (or
 * {@code &v=...} if the URL already carries a query string) so the URL
 * deterministically changes whenever {@link User#getUpdatedAt()} bumps,
 * which the {@code @PreUpdate} hook on {@link User} does on every save.
 *
 * <p>The version is stable for the same avatar version, so re-fetching
 * the same DTO does not force re-downloads.
 */
public final class AvatarUrls {
    private AvatarUrls() {}

    /** Build a cache-busting URL for the user's avatar, or {@code null}. */
    public static String versioned(User user) {
        if (user == null) return null;
        return versioned(user.getAvatarUrl(), user.getUpdatedAt());
    }

    /** Build a cache-busting URL given a raw URL and a version timestamp. */
    public static String versioned(String rawUrl, LocalDateTime updatedAt) {
        if (rawUrl == null || rawUrl.isEmpty()) return null;
        // Skip if already versioned (idempotent).
        if (rawUrl.contains("v=")) return rawUrl;
        long v = updatedAt != null
                ? updatedAt.toEpochSecond(ZoneOffset.UTC)
                : 0L;
        char sep = rawUrl.contains("?") ? '&' : '?';
        return rawUrl + sep + "v=" + v;
    }
}
