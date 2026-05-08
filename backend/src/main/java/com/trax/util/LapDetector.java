package com.trax.util;

import com.trax.model.TrailPoint;
import java.util.List;

/**
 * Lap detection and snapping utilities.
 * Reusable for Lap Ride and Race Ride features.
 */
public class LapDetector {

    public static final double LAP_CLOSE_THRESHOLD_KM = 0.05;  // 50 meters
    // A small backyard lap can have a max excursion of only ~50 m from the
    // start, so we keep the excursion bar aligned with the closing threshold.
    public static final double MIN_LAP_EXCURSION_KM = 0.05;    // 50 meters
    public static final double MIN_LAP_DISTANCE_KM = 0.1;      // 100 meters

    /**
     * Checks if a set of points forms a valid lap:
     * 1. End point is close to start point (within threshold)
     * 2. Path traveled away from start (not just GPS jitter in place)
     * 3. Total distance is above minimum
     */
    public static boolean isLapComplete(
            double startLat, double startLng,
            double endLat, double endLng,
            List<TrailPoint> points) {

        // 1. Closing distance check
        double closingDist = GeoUtils.haversineKm(startLat, startLng, endLat, endLng);
        if (closingDist > LAP_CLOSE_THRESHOLD_KM) return false;

        // 2. Must have traveled away from start
        double maxDistFromStart = 0;
        for (TrailPoint p : points) {
            double d = GeoUtils.haversineKm(startLat, startLng, p.getLatitude(), p.getLongitude());
            if (d > maxDistFromStart) maxDistFromStart = d;
        }
        if (maxDistFromStart < MIN_LAP_EXCURSION_KM) return false;

        // 3. Total distance check
        double totalDist = 0;
        for (int i = 1; i < points.size(); i++) {
            totalDist += GeoUtils.haversineKm(
                    points.get(i - 1).getLatitude(), points.get(i - 1).getLongitude(),
                    points.get(i).getLatitude(), points.get(i).getLongitude());
        }
        if (totalDist < MIN_LAP_DISTANCE_KM) return false;

        return true;
    }

    /**
     * For lap trails, snaps the last point to the first point's coordinates
     * to close the loop cleanly.
     */
    public static void snapToLap(List<TrailPoint> points) {
        if (points.size() < 2) return;
        TrailPoint first = points.get(0);
        TrailPoint last = points.get(points.size() - 1);
        last.setLatitude(first.getLatitude());
        last.setLongitude(first.getLongitude());
        last.setAltitude(first.getAltitude());
    }
}
