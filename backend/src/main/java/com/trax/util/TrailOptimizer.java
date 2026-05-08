package com.trax.util;

import com.trax.model.TrailPoint;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

public class TrailOptimizer {

    private static final double MAX_SPEED_KMH = 100.0;
    private static final double MIN_POINT_DISTANCE_KM = 0.003; // 3 meters
    private static final double OUTLIER_THRESHOLD_KM = 0.05; // 50 meters
    // 2 m simplification tolerance preserves road curvature while still
    // removing only collinear samples on straight segments.
    private static final double DP_EPSILON_KM = 0.002;

    public static List<TrailPoint> optimizePoints(List<TrailPoint> raw) {
        if (raw.size() < 3) return new ArrayList<>(raw);

        List<TrailPoint> result = raw;
        result = filterBySpeed(result);
        result = filterByMinDistance(result);
        result = filterOutliers(result);
        result = douglasPeucker(result, DP_EPSILON_KM);

        // Re-index sequence
        for (int i = 0; i < result.size(); i++) {
            result.get(i).setSequenceIndex(i);
        }
        return result;
    }

    // Remove points with impossible speed jumps
    private static List<TrailPoint> filterBySpeed(List<TrailPoint> points) {
        if (points.size() < 2) return new ArrayList<>(points);
        List<TrailPoint> result = new ArrayList<>();
        result.add(points.get(0));

        for (int i = 1; i < points.size(); i++) {
            TrailPoint prev = result.get(result.size() - 1);
            TrailPoint curr = points.get(i);
            double distKm = GeoUtils.haversineKm(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());

            if (prev.getTimestamp() != null && curr.getTimestamp() != null) {
                long seconds = Duration.between(prev.getTimestamp(), curr.getTimestamp()).toSeconds();
                if (seconds > 0) {
                    double speedKmh = (distKm / seconds) * 3600.0;
                    if (speedKmh > MAX_SPEED_KMH) continue; // skip this point
                }
            }
            result.add(curr);
        }
        return result;
    }

    // Remove points too close together (GPS jitter)
    private static List<TrailPoint> filterByMinDistance(List<TrailPoint> points) {
        if (points.size() < 2) return new ArrayList<>(points);
        List<TrailPoint> result = new ArrayList<>();
        result.add(points.get(0));

        for (int i = 1; i < points.size(); i++) {
            TrailPoint prev = result.get(result.size() - 1);
            TrailPoint curr = points.get(i);
            double distKm = GeoUtils.haversineKm(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
            if (distKm >= MIN_POINT_DISTANCE_KM) {
                result.add(curr);
            }
        }
        // Always keep last point
        TrailPoint last = points.get(points.size() - 1);
        if (!result.get(result.size() - 1).equals(last)) {
            result.add(last);
        }
        return result;
    }

    // Remove outliers that deviate too far from the line between neighbors
    private static List<TrailPoint> filterOutliers(List<TrailPoint> points) {
        if (points.size() < 3) return new ArrayList<>(points);
        List<TrailPoint> result = new ArrayList<>();
        result.add(points.get(0));

        for (int i = 1; i < points.size() - 1; i++) {
            TrailPoint prev = points.get(i - 1);
            TrailPoint curr = points.get(i);
            TrailPoint next = points.get(i + 1);

            double deviation = pointToLineDistance(
                    curr.getLatitude(), curr.getLongitude(),
                    prev.getLatitude(), prev.getLongitude(),
                    next.getLatitude(), next.getLongitude());

            if (deviation <= OUTLIER_THRESHOLD_KM) {
                result.add(curr);
            }
        }
        result.add(points.get(points.size() - 1));
        return result;
    }

    // Douglas-Peucker line simplification
    private static List<TrailPoint> douglasPeucker(List<TrailPoint> points, double epsilon) {
        if (points.size() < 3) return new ArrayList<>(points);

        double maxDist = 0;
        int maxIdx = 0;
        TrailPoint first = points.get(0);
        TrailPoint last = points.get(points.size() - 1);

        for (int i = 1; i < points.size() - 1; i++) {
            double dist = pointToLineDistance(
                    points.get(i).getLatitude(), points.get(i).getLongitude(),
                    first.getLatitude(), first.getLongitude(),
                    last.getLatitude(), last.getLongitude());
            if (dist > maxDist) {
                maxDist = dist;
                maxIdx = i;
            }
        }

        if (maxDist > epsilon) {
            List<TrailPoint> left = douglasPeucker(points.subList(0, maxIdx + 1), epsilon);
            List<TrailPoint> right = douglasPeucker(points.subList(maxIdx, points.size()), epsilon);
            List<TrailPoint> result = new ArrayList<>(left);
            result.addAll(right.subList(1, right.size()));
            return result;
        } else {
            List<TrailPoint> result = new ArrayList<>();
            result.add(first);
            result.add(last);
            return result;
        }
    }

    // Perpendicular distance from point to line (in km)
    private static double pointToLineDistance(
            double pLat, double pLng,
            double aLat, double aLng,
            double bLat, double bLng) {
        double ab = GeoUtils.haversineKm(aLat, aLng, bLat, bLng);
        if (ab < 0.0001) return GeoUtils.haversineKm(pLat, pLng, aLat, aLng);

        double ap = GeoUtils.haversineKm(aLat, aLng, pLat, pLng);
        double bp = GeoUtils.haversineKm(bLat, bLng, pLat, pLng);

        // Use Heron's formula for triangle area
        double s = (ab + ap + bp) / 2.0;
        double areaSquared = s * (s - ab) * (s - ap) * (s - bp);
        if (areaSquared < 0) areaSquared = 0;
        double area = Math.sqrt(areaSquared);
        return (2.0 * area) / ab;
    }
}
