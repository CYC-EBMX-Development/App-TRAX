package com.trax.util;

import com.trax.model.TrailPoint;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class LapDetectorTest {

    private static TrailPoint point(double lat, double lng) {
        TrailPoint p = new TrailPoint();
        p.setLatitude(lat);
        p.setLongitude(lng);
        p.setAltitude(0);
        return p;
    }

    /** Build a roughly rectangular loop centred at (lat, lng) with ~side meters. */
    private static List<TrailPoint> rectangleLap(double lat, double lng, double sideMeters) {
        double dLat = sideMeters / 111_000.0;
        double dLng = sideMeters / (111_000.0 * Math.cos(Math.toRadians(lat)));
        List<TrailPoint> pts = new ArrayList<>();
        pts.add(point(lat, lng));
        pts.add(point(lat + dLat, lng));
        pts.add(point(lat + dLat, lng + dLng));
        pts.add(point(lat, lng + dLng));
        pts.add(point(lat, lng)); // close
        return pts;
    }

    @Test
    void completeRectangleLapIsDetected() {
        List<TrailPoint> pts = rectangleLap(31.0, 121.0, 80.0);
        TrailPoint start = pts.get(0);
        TrailPoint end = pts.get(pts.size() - 1);
        assertThat(LapDetector.isLapComplete(
                start.getLatitude(), start.getLongitude(),
                end.getLatitude(), end.getLongitude(),
                pts)).isTrue();
    }

    @Test
    void openLapReturnsFalse() {
        // End far from start (open path)
        List<TrailPoint> pts = new ArrayList<>();
        pts.add(point(31.0, 121.0));
        pts.add(point(31.001, 121.001));
        pts.add(point(31.002, 121.002));
        assertThat(LapDetector.isLapComplete(
                31.0, 121.0, 31.002, 121.002, pts)).isFalse();
    }

    @Test
    void gpsJitterInPlaceIsNotALap() {
        // Closing distance OK, but never goes further than a few meters
        List<TrailPoint> pts = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            pts.add(point(31.0 + i * 1e-6, 121.0 + i * 1e-6));
        }
        assertThat(LapDetector.isLapComplete(31.0, 121.0, 31.000001, 121.000001, pts)).isFalse();
    }

    @Test
    void snapToLapAlignsLastPointToFirst() {
        List<TrailPoint> pts = rectangleLap(31.0, 121.0, 100.0);
        // perturb last point slightly
        pts.get(pts.size() - 1).setLatitude(31.0001);
        LapDetector.snapToLap(pts);
        assertThat(pts.get(pts.size() - 1).getLatitude()).isEqualTo(pts.get(0).getLatitude());
        assertThat(pts.get(pts.size() - 1).getLongitude()).isEqualTo(pts.get(0).getLongitude());
    }

    @Test
    void snapToLapWithTooFewPointsIsNoop() {
        List<TrailPoint> pts = new ArrayList<>();
        pts.add(point(31.0, 121.0));
        LapDetector.snapToLap(pts); // should not throw
        assertThat(pts).hasSize(1);
    }
}
