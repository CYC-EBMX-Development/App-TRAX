package com.trax.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.client.SimpleClientHttpRequestFactory;

import java.net.InetSocketAddress;
import java.net.Proxy;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Fetches a closed-loop driving route around a center point via the Google
 * Directions API and returns it as decoded [lat, lng] coordinates.
 *
 * Uses local HTTP proxy 127.0.0.1:7897 because the host network blocks direct
 * access to maps.googleapis.com.
 */
@Service
public class RouteService {

    @Value("${app.google.maps-api-key:AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng}")
    private String apiKey;

    @Value("${app.proxy.host:127.0.0.1}")
    private String proxyHost;

    @Value("${app.proxy.port:7897}")
    private int proxyPort;

    private RestTemplate restTemplate;

    private RestTemplate getRestTemplate() {
        if (restTemplate == null) {
            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setProxy(new Proxy(Proxy.Type.HTTP, new InetSocketAddress(proxyHost, proxyPort)));
            factory.setConnectTimeout(8000);
            factory.setReadTimeout(15000);
            restTemplate = new RestTemplate(factory);
        }
        return restTemplate;
    }

    /**
     * Fetch a closed-loop driving route around (lat, lng). Returns a list of
     * [lat, lng] points, or null when the API fails.
     */
    public List<double[]> fetchRoute(double lat, double lng) {
        // Build 4 waypoints forming a clockwise circuit: NE → SE → SW → NW
        // Do NOT use optimize:true — it reorders waypoints and causes backtracking
        double offsetDeg = 500.0 / 111320.0;
        double lngScale = 1.0 / Math.cos(Math.toRadians(lat));

        String origin = lat + "," + lng;
        String waypoints = ""
                + (lat + offsetDeg) + "," + (lng + offsetDeg * lngScale) + "|"
                + (lat - offsetDeg) + "," + (lng + offsetDeg * lngScale) + "|"
                + (lat - offsetDeg) + "," + (lng - offsetDeg * lngScale) + "|"
                + (lat + offsetDeg) + "," + (lng - offsetDeg * lngScale);

        String url = "https://maps.googleapis.com/maps/api/directions/json"
                + "?origin=" + origin
                + "&destination=" + origin
                + "&waypoints=" + waypoints
                + "&mode=driving"
                + "&key=" + apiKey;

        try {
            ResponseEntity<Map> resp = getRestTemplate().getForEntity(url, Map.class);
            Map body = resp.getBody();
            if (body == null) return null;
            Object status = body.get("status");
            if (!"OK".equals(status)) {
                System.err.println("Directions API status: " + status + " for " + origin);
                return null;
            }
            List<Map<String, Object>> routes = (List<Map<String, Object>>) body.get("routes");
            if (routes == null || routes.isEmpty()) return null;
            Map<String, Object> overview = (Map<String, Object>) routes.get(0).get("overview_polyline");
            if (overview == null) return null;
            String polyline = (String) overview.get("points");
            return decodePolyline(polyline);
        } catch (Exception e) {
            System.err.println("RouteService.fetchRoute failed: " + e.getMessage());
            return null;
        }
    }

    /** Decode a Google encoded polyline to a list of [lat, lng] doubles. */
    public static List<double[]> decodePolyline(String encoded) {
        List<double[]> points = new ArrayList<>();
        int index = 0, len = encoded.length();
        int lat = 0, lng = 0;
        while (index < len) {
            int b, shift = 0, result = 0;
            do {
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
            lat += dlat;

            shift = 0; result = 0;
            do {
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
            lng += dlng;

            points.add(new double[]{lat / 1e5, lng / 1e5});
        }
        return points;
    }
}
