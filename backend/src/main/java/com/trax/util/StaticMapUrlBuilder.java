package com.trax.util;

import com.trax.model.TrailPoint;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Builds a Google Static Maps URL that auto-fits a polyline route, used
 * as the thumbnail for newly created trails. Mirrors the client-side
 * `StaticMapUrl.forRoute()` so trail cards render the same image without
 * an extra round-trip.
 */
public final class StaticMapUrlBuilder {
    private static final String API_KEY = "AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng";
    private static final String BASE = "https://maps.googleapis.com/maps/api/staticmap";

    private StaticMapUrlBuilder() {}

    /**
     * Returns a static-map URL rendering [points] as a colored polyline.
     * Returns null when [points] is empty.
     */
    public static String forTrailPoints(List<TrailPoint> points) {
        if (points == null || points.isEmpty()) return null;
        // Down-sample very long routes so the URL stays under the ~8 KB
        // limit imposed by the Static Maps API.
        List<TrailPoint> sampled = downsample(points, 120);
        String encoded = encodePolyline(sampled);
        TrailPoint start = points.get(0);
        TrailPoint end = points.get(points.size() - 1);

        StringBuilder qs = new StringBuilder();
        append(qs, "size", "240x240");
        append(qs, "scale", "2");
        append(qs, "maptype", "roadmap");
        append(qs, "path", "color:0xFF6A00FF|weight:4|enc:" + encoded);
        append(qs, "key", API_KEY);
        qs.append("&markers=").append(enc("color:green|label:S|"
                + start.getLatitude() + "," + start.getLongitude()));
        if (points.size() > 1) {
            qs.append("&markers=").append(enc("color:red|label:E|"
                    + end.getLatitude() + "," + end.getLongitude()));
        }
        return BASE + "?" + qs;
    }

    private static void append(StringBuilder qs, String k, String v) {
        if (qs.length() > 0) qs.append('&');
        qs.append(enc(k)).append('=').append(enc(v));
    }

    private static String enc(String v) {
        return URLEncoder.encode(v, StandardCharsets.UTF_8);
    }

    private static List<TrailPoint> downsample(List<TrailPoint> pts, int max) {
        if (pts.size() <= max) return pts;
        double step = pts.size() / (double) max;
        java.util.List<TrailPoint> out = new java.util.ArrayList<>(max + 1);
        for (int i = 0; i < max; i++) {
            out.add(pts.get((int) Math.floor(i * step)));
        }
        TrailPoint last = pts.get(pts.size() - 1);
        if (out.get(out.size() - 1) != last) out.add(last);
        return out;
    }

    /** Google encoded polyline algorithm. */
    private static String encodePolyline(List<TrailPoint> points) {
        StringBuilder sb = new StringBuilder();
        long lastLat = 0, lastLng = 0;
        for (TrailPoint p : points) {
            long lat = Math.round(p.getLatitude() * 1e5);
            long lng = Math.round(p.getLongitude() * 1e5);
            encodeValue(lat - lastLat, sb);
            encodeValue(lng - lastLng, sb);
            lastLat = lat;
            lastLng = lng;
        }
        return sb.toString();
    }

    private static void encodeValue(long v, StringBuilder sb) {
        long value = v < 0 ? ~(v << 1) : (v << 1);
        while (value >= 0x20) {
            sb.appendCodePoint((int) ((0x20 | (value & 0x1f)) + 63));
            value >>= 5;
        }
        sb.appendCodePoint((int) (value + 63));
    }
}
