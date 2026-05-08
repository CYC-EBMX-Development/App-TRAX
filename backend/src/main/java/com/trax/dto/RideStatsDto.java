package com.trax.dto;

import java.util.ArrayList;
import java.util.List;

public class RideStatsDto {
    private Long rideId;
    private String status;
    private long durationSeconds;
    private double distanceKm;
    private double avgSpeedKmh;
    private double maxSpeedKmh;
    private double elevationMeters;
    private double currentLatitude;
    private double currentLongitude;
    private Integer targetLaps;
    private Integer completedLaps;
    private List<RideLapDto> laps = new ArrayList<>();

    public Long getRideId() { return rideId; }
    public void setRideId(Long rideId) { this.rideId = rideId; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public long getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(long durationSeconds) { this.durationSeconds = durationSeconds; }
    public double getDistanceKm() { return distanceKm; }
    public void setDistanceKm(double distanceKm) { this.distanceKm = distanceKm; }
    public double getAvgSpeedKmh() { return avgSpeedKmh; }
    public void setAvgSpeedKmh(double avgSpeedKmh) { this.avgSpeedKmh = avgSpeedKmh; }
    public double getMaxSpeedKmh() { return maxSpeedKmh; }
    public void setMaxSpeedKmh(double maxSpeedKmh) { this.maxSpeedKmh = maxSpeedKmh; }
    public double getElevationMeters() { return elevationMeters; }
    public void setElevationMeters(double elevationMeters) { this.elevationMeters = elevationMeters; }
    public double getCurrentLatitude() { return currentLatitude; }
    public void setCurrentLatitude(double currentLatitude) { this.currentLatitude = currentLatitude; }
    public double getCurrentLongitude() { return currentLongitude; }
    public void setCurrentLongitude(double currentLongitude) { this.currentLongitude = currentLongitude; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public Integer getCompletedLaps() { return completedLaps; }
    public void setCompletedLaps(Integer completedLaps) { this.completedLaps = completedLaps; }
    public List<RideLapDto> getLaps() { return laps; }
    public void setLaps(List<RideLapDto> laps) { this.laps = laps; }
}
