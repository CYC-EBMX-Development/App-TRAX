package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "history_ride_points")
public class HistoryRidePoint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long originalId;
    private Long originalRideId;
    private Long historyRideId;
    private double latitude;
    private double longitude;
    private double speed;
    private double altitude;
    private LocalDateTime timestamp;
    private LocalDateTime archivedAt;

    @PrePersist
    protected void onArchive() {
        archivedAt = LocalDateTime.now();
    }

    public static HistoryRidePoint fromRidePoint(RidePoint p, Long historyRideId) {
        HistoryRidePoint h = new HistoryRidePoint();
        h.originalId = p.getId();
        h.originalRideId = p.getRide() != null ? p.getRide().getId() : null;
        h.historyRideId = historyRideId;
        h.latitude = p.getLatitude();
        h.longitude = p.getLongitude();
        h.speed = p.getSpeed();
        h.altitude = p.getAltitude();
        h.timestamp = p.getTimestamp();
        return h;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getOriginalId() { return originalId; }
    public void setOriginalId(Long originalId) { this.originalId = originalId; }
    public Long getOriginalRideId() { return originalRideId; }
    public void setOriginalRideId(Long originalRideId) { this.originalRideId = originalRideId; }
    public Long getHistoryRideId() { return historyRideId; }
    public void setHistoryRideId(Long historyRideId) { this.historyRideId = historyRideId; }
    public double getLatitude() { return latitude; }
    public void setLatitude(double latitude) { this.latitude = latitude; }
    public double getLongitude() { return longitude; }
    public void setLongitude(double longitude) { this.longitude = longitude; }
    public double getSpeed() { return speed; }
    public void setSpeed(double speed) { this.speed = speed; }
    public double getAltitude() { return altitude; }
    public void setAltitude(double altitude) { this.altitude = altitude; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
    public LocalDateTime getArchivedAt() { return archivedAt; }
    public void setArchivedAt(LocalDateTime archivedAt) { this.archivedAt = archivedAt; }
}
