package com.trax.util;

import java.util.ArrayList;
import java.util.List;

public class PolylineDecoder {

    /**
     * Decode a Google Encoded Polyline string into a list of [lat, lng] pairs.
     */
    public static List<double[]> decode(String encoded) {
        List<double[]> points = new ArrayList<>();
        int index = 0;
        int lat = 0;
        int lng = 0;

        while (index < encoded.length()) {
            int shift = 0;
            int result = 0;
            int b;
            do {
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1F) << shift;
                shift += 5;
            } while (b >= 0x20);
            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

            shift = 0;
            result = 0;
            do {
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1F) << shift;
                shift += 5;
            } while (b >= 0x20);
            lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

            points.add(new double[]{lat / 1e5, lng / 1e5});
        }
        return points;
    }
}
