package com.trax.dto;

import java.util.List;

public class TrailCreateRequest {
    private String name;
    private String type; // free_ride, lap
    private String difficulty;
    private String location;
    private boolean isPublic = true;
    private List<TrailPointData> points;

    public static class TrailPointData {
        private double latitude;
        private double longitude;
        private double altitude;
        private String timestamp;

        public double getLatitude() { return latitude; }
        public void setLatitude(double latitude) { this.latitude = latitude; }
        public double getLongitude() { return longitude; }
        public void setLongitude(double longitude) { this.longitude = longitude; }
        public double getAltitude() { return altitude; }
        public void setAltitude(double altitude) { this.altitude = altitude; }
        public String getTimestamp() { return timestamp; }
        public void setTimestamp(String timestamp) { this.timestamp = timestamp; }
    }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getDifficulty() { return difficulty; }
    public void setDifficulty(String difficulty) { this.difficulty = difficulty; }
    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }
    public boolean isPublic() { return isPublic; }
    public void setPublic(boolean isPublic) { this.isPublic = isPublic; }
    public List<TrailPointData> getPoints() { return points; }
    public void setPoints(List<TrailPointData> points) { this.points = points; }
}
