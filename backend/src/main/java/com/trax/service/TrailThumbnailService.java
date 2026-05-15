package com.trax.service;

import com.trax.model.TrailPoint;
import com.trax.util.StaticMapUrlBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLConnection;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

/**
 * Generates and persists a Google Static Maps PNG thumbnail for a trail
 * at creation time, so clients (especially iOS users in restricted
 * networks) don't need to hit Google directly.
 *
 * <p>Output is written to {@code <images-dir>/trails/<trailId>.png}, then
 * served via the existing {@code /images/**} static resource handler.
 */
@Service
public class TrailThumbnailService {
    private static final Logger logger = LoggerFactory.getLogger(TrailThumbnailService.class);
    private static final int CONNECT_TIMEOUT_MS = 8_000;
    private static final int READ_TIMEOUT_MS = 15_000;
    private static final int MAX_BYTES = 2 * 1024 * 1024; // 2 MB

    private final Path trailsDir;

    public TrailThumbnailService(
            @Value("${app.images.dir:/Users/cyc_joshua/Documents/CYC/TRAX/App-TRAX/backend/images}") String imagesDir) {
        this.trailsDir = Paths.get(imagesDir, "trails");
        try {
            Files.createDirectories(trailsDir);
        } catch (IOException e) {
            logger.error("Failed to create trail thumbnails dir {}", trailsDir, e);
        }
    }

    /**
     * Downloads the static-map PNG for [points] and writes it to disk.
     * Returns the path the client should use (e.g.
     * {@code "/images/trails/42.png"}), or {@code null} when the fetch
     * failed — callers should treat that as "no pre-baked thumbnail" and
     * fall back to the dynamic client-side render.
     */
    public String generateAndStore(Long trailId, List<TrailPoint> points) {
        if (trailId == null || points == null || points.isEmpty()) return null;
        final String url = StaticMapUrlBuilder.forTrailPoints(points);
        if (url == null) return null;

        final Path file = trailsDir.resolve(trailId + ".png");
        try {
            URLConnection conn = new URL(url).openConnection();
            conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
            conn.setReadTimeout(READ_TIMEOUT_MS);
            conn.setRequestProperty("User-Agent", "TRAX-Backend/1.0");

            try (InputStream in = conn.getInputStream();
                 FileOutputStream out = new FileOutputStream(file.toFile())) {
                byte[] buf = new byte[8192];
                int n;
                int total = 0;
                while ((n = in.read(buf)) != -1) {
                    out.write(buf, 0, n);
                    total += n;
                    if (total > MAX_BYTES) {
                        logger.warn("Static map for trail {} exceeded {} bytes; aborting", trailId, MAX_BYTES);
                        Files.deleteIfExists(file);
                        return null;
                    }
                }
                if (total < 200) {
                    logger.warn("Static map for trail {} too small ({} bytes); discarding", trailId, total);
                    Files.deleteIfExists(file);
                    return null;
                }
            }
        } catch (IOException e) {
            logger.warn("Failed to fetch static map for trail {}: {}", trailId, e.getMessage());
            try { Files.deleteIfExists(file); } catch (IOException ignored) {}
            return null;
        }
        return "/images/trails/" + trailId + ".png";
    }
}
