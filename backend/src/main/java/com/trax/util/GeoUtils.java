package com.trax.util;

import java.util.List;

public class GeoUtils {
    private static final double EARTH_RADIUS_KM = 6371.0;

    public static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_KM * c;
    }

    /**
     * Perpendicular distance (km) from point P to segment AB on Earth's
     * surface. Falls back to endpoint distance when the foot of the
     * perpendicular lies outside the segment.
     */
    public static double pointToSegmentKm(
            double pLat, double pLng,
            double aLat, double aLng,
            double bLat, double bLng) {
        double ab = haversineKm(aLat, aLng, bLat, bLng);
        double ap = haversineKm(aLat, aLng, pLat, pLng);
        double bp = haversineKm(bLat, bLng, pLat, pLng);
        if (ab < 1e-7) return ap;

        double cosA = (ab * ab + ap * ap - bp * bp) / (2 * ab * ap + 1e-12);
        if (cosA <= 0) return ap;
        double cosB = (ab * ab + bp * bp - ap * ap) / (2 * ab * bp + 1e-12);
        if (cosB <= 0) return bp;

        double s = (ab + ap + bp) / 2.0;
        double areaSq = s * (s - ab) * (s - ap) * (s - bp);
        if (areaSq < 0) areaSq = 0;
        double area = Math.sqrt(areaSq);
        return (2.0 * area) / ab;
    }

    /**
     * Minimum distance (meters) from point P to a polyline (list of
     * {lat, lng} arrays).
     */
    public static double pointToPolylineMeters(double pLat, double pLng, List<double[]> polyline) {
        if (polyline == null || polyline.isEmpty()) return Double.MAX_VALUE;
        if (polyline.size() == 1) {
            return haversineKm(pLat, pLng, polyline.get(0)[0], polyline.get(0)[1]) * 1000.0;
        }
        double bestKm = Double.MAX_VALUE;
        for (int i = 0; i < polyline.size() - 1; i++) {
            double[] a = polyline.get(i);
            double[] b = polyline.get(i + 1);
            double d = pointToSegmentKm(pLat, pLng, a[0], a[1], b[0], b[1]);
            if (d < bestKm) bestKm = d;
        }
        return bestKm * 1000.0;
    }

    /**
     * Project point P onto the polyline; returns the index of the nearest
     * segment together with the segment fraction (0..1 along that segment)
     * and the distance in meters. Returns null when the polyline has fewer
     * than 2 points.
     */
    public static Projection projectOntoPolyline(double pLat, double pLng, List<double[]> polyline) {
        if (polyline == null || polyline.size() < 2) return null;
        int bestSeg = 0;
        double bestKm = Double.MAX_VALUE;
        double bestFrac = 0.0;
        for (int i = 0; i < polyline.size() - 1; i++) {
            double[] a = polyline.get(i);
            double[] b = polyline.get(i + 1);
            double ab = haversineKm(a[0], a[1], b[0], b[1]);
            double ap = haversineKm(a[0], a[1], pLat, pLng);
            double bp = haversineKm(b[0], b[1], pLat, pLng);
            double dKm;
            double frac;
            if (ab < 1e-7) {
                dKm = ap;
                frac = 0.0;
            } else {
                double cosA = (ab * ab + ap * ap - bp * bp) / (2 * ab * ap + 1e-12);
                double cosB = (ab * ab + bp * bp - ap * ap) / (2 * ab * bp + 1e-12);
                if (cosA <= 0) {
                    dKm = ap;
                    frac = 0.0;
                } else if (cosB <= 0) {
                    dKm = bp;
                    frac = 1.0;
                } else {
                    double s = (ab + ap + bp) / 2.0;
                    double areaSq = s * (s - ab) * (s - ap) * (s - bp);
                    if (areaSq < 0) areaSq = 0;
                    double area = Math.sqrt(areaSq);
                    dKm = (2.0 * area) / ab;
                    double along = ap * cosA;
                    frac = along / ab;
                    if (frac < 0) frac = 0;
                    if (frac > 1) frac = 1;
                }
            }
            if (dKm < bestKm) {
                bestKm = dKm;
                bestSeg = i;
                bestFrac = frac;
            }
        }
        return new Projection(bestSeg, bestFrac, bestKm * 1000.0);
    }

    public static class Projection {
        public final int segmentIndex;
        public final double segmentFraction;
        public final double distanceMeters;

        public Projection(int segmentIndex, double segmentFraction, double distanceMeters) {
            this.segmentIndex = segmentIndex;
            this.segmentFraction = segmentFraction;
            this.distanceMeters = distanceMeters;
        }
    }
}
