package com.trax.util;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class GeoUtilsTest {

    @Test
    void haversineSamePointIsZero() {
        assertThat(GeoUtils.haversineKm(31.2304, 121.4737, 31.2304, 121.4737))
                .isCloseTo(0.0, within(1e-6));
    }

    @Test
    void haversineShanghaiToBeijingIsAroundOneThousandKm() {
        // SHA 31.2304,121.4737 → BJ 39.9042,116.4074, ≈ 1067 km
        double dist = GeoUtils.haversineKm(31.2304, 121.4737, 39.9042, 116.4074);
        assertThat(dist).isCloseTo(1067.0, within(10.0));
    }

    @Test
    void pointOnSegmentReturnsNearZero() {
        // Segment from (0,0) to (0,1) deg; point at midpoint should be ~0
        double d = GeoUtils.pointToSegmentKm(0.0, 0.5, 0.0, 0.0, 0.0, 1.0);
        assertThat(d).isLessThan(0.01);
    }

    @Test
    void pointBeforeSegmentFallsBackToEndpointDistance() {
        // P at (0,-1), segment (0,0)->(0,1). Foot is at A, distance = haversine(P,A)
        double dSeg = GeoUtils.pointToSegmentKm(0.0, -1.0, 0.0, 0.0, 0.0, 1.0);
        double dA = GeoUtils.haversineKm(0.0, -1.0, 0.0, 0.0);
        assertThat(dSeg).isCloseTo(dA, within(0.01));
    }

    @Test
    void pointToPolylineEmptyReturnsMaxValue() {
        assertThat(GeoUtils.pointToPolylineMeters(0, 0, List.of()))
                .isEqualTo(Double.MAX_VALUE);
    }

    @Test
    void pointToPolylineSinglePointReturnsHaversineMeters() {
        double m = GeoUtils.pointToPolylineMeters(0.0, 0.0, List.of(new double[]{0.0, 0.01}));
        // 0.01 deg lon at equator ≈ 1.113 km = 1113 m
        assertThat(m).isCloseTo(1113.0, within(5.0));
    }

    @Test
    void projectionReturnsNullForShortPolyline() {
        assertThat(GeoUtils.projectOntoPolyline(0, 0, null)).isNull();
        assertThat(GeoUtils.projectOntoPolyline(0, 0, List.of(new double[]{0, 0}))).isNull();
    }

    @Test
    void projectionAtMidpointReturnsHalfFraction() {
        List<double[]> poly = List.of(new double[]{0.0, 0.0}, new double[]{0.0, 1.0});
        GeoUtils.Projection p = GeoUtils.projectOntoPolyline(0.0, 0.5, poly);
        assertThat(p).isNotNull();
        assertThat(p.segmentIndex).isZero();
        assertThat(p.segmentFraction).isCloseTo(0.5, within(0.01));
        assertThat(p.distanceMeters).isLessThan(10.0);
    }
}
