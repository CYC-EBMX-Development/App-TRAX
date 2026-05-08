package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "history_ride_records")
public class HistoryRideRecord {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long originalId;
    private Long userId;
    private Long trailId;
    private Long originalBicycleId;
    private Long historyBicycleId;
    private LocalDateTime startTime;
    private LocalDateTime endTime;
    private Double distance;
    private Double avgSpeed;
    private Double maxSpeed;
    private Double elevation;
    private String weather;
    private String status;
    private String mode;
    private Double totalPausedSeconds;
    private LocalDateTime lastPausedAt;
    private LocalDateTime archivedAt;

    @PrePersist
    protected void onArchive() {
        archivedAt = LocalDateTime.now();
    }

    public static HistoryRideRecord fromRideRecord(RideRecord r, Long historyBicycleId) {
        HistoryRideRecord h = new HistoryRideRecord();
        h.originalId = r.getId();
        h.userId = r.getUser() != null ? r.getUser().getId() : null;
        h.trailId = r.getTrail() != null ? r.getTrail().getId() : null;
        h.originalBicycleId = r.getBicycle() != null ? r.getBicycle().getId() : null;
        h.historyBicycleId = historyBicycleId;
        h.startTime = r.getStartTime();
        h.endTime = r.getEndTime();
        h.distance = r.getDistance();
        h.avgSpeed = r.getAvgSpeed();
        h.maxSpeed = r.getMaxSpeed();
        h.elevation = r.getElevation();
        h.weather = r.getWeather();
        h.status = r.getStatus();
        h.mode = r.getMode();
        h.totalPausedSeconds = r.getTotalPausedSeconds();
        h.lastPausedAt = r.getLastPausedAt();
        return h;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getOriginalId() { return originalId; }
    public void setOriginalId(Long originalId) { this.originalId = originalId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public Long getOriginalBicycleId() { return originalBicycleId; }
    public void setOriginalBicycleId(Long originalBicycleId) { this.originalBicycleId = originalBicycleId; }
    public Long getHistoryBicycleId() { return historyBicycleId; }
    public void setHistoryBicycleId(Long historyBicycleId) { this.historyBicycleId = historyBicycleId; }
    public LocalDateTime getStartTime() { return startTime; }
    public void setStartTime(LocalDateTime startTime) { this.startTime = startTime; }
    public LocalDateTime getEndTime() { return endTime; }
    public void setEndTime(LocalDateTime endTime) { this.endTime = endTime; }
    public Double getDistance() { return distance; }
    public void setDistance(Double distance) { this.distance = distance; }
    public Double getAvgSpeed() { return avgSpeed; }
    public void setAvgSpeed(Double avgSpeed) { this.avgSpeed = avgSpeed; }
    public Double getMaxSpeed() { return maxSpeed; }
    public void setMaxSpeed(Double maxSpeed) { this.maxSpeed = maxSpeed; }
    public Double getElevation() { return elevation; }
    public void setElevation(Double elevation) { this.elevation = elevation; }
    public String getWeather() { return weather; }
    public void setWeather(String weather) { this.weather = weather; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getMode() { return mode; }
    public void setMode(String mode) { this.mode = mode; }
    public Double getTotalPausedSeconds() { return totalPausedSeconds; }
    public void setTotalPausedSeconds(Double totalPausedSeconds) { this.totalPausedSeconds = totalPausedSeconds; }
    public LocalDateTime getLastPausedAt() { return lastPausedAt; }
    public void setLastPausedAt(LocalDateTime lastPausedAt) { this.lastPausedAt = lastPausedAt; }
    public LocalDateTime getArchivedAt() { return archivedAt; }
    public void setArchivedAt(LocalDateTime archivedAt) { this.archivedAt = archivedAt; }
}
