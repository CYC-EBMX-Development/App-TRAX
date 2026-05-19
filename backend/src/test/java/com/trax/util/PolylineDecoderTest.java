package com.trax.util;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class PolylineDecoderTest {

    @Test
    void decodesKnownGooglePolylineExample() {
        // Canonical example from Google polyline docs:
        // "_p~iF~ps|U_ulLnnqC_mqNvxq`@" → 3 points
        List<double[]> points = PolylineDecoder.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
        assertThat(points).hasSize(3);
        assertThat(points.get(0)[0]).isCloseTo(38.5, within(0.001));
        assertThat(points.get(0)[1]).isCloseTo(-120.2, within(0.001));
        assertThat(points.get(1)[0]).isCloseTo(40.7, within(0.001));
        assertThat(points.get(1)[1]).isCloseTo(-120.95, within(0.001));
        assertThat(points.get(2)[0]).isCloseTo(43.252, within(0.001));
        assertThat(points.get(2)[1]).isCloseTo(-126.453, within(0.001));
    }

    @Test
    void decodesSinglePoint() {
        // "_p~iF~ps|U" → (38.5, -120.2)
        List<double[]> points = PolylineDecoder.decode("_p~iF~ps|U");
        assertThat(points).hasSize(1);
        assertThat(points.get(0)[0]).isCloseTo(38.5, within(0.001));
        assertThat(points.get(0)[1]).isCloseTo(-120.2, within(0.001));
    }
}
