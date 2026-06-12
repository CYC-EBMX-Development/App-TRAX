package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "ride_points")
public class RidePoint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_id")
    private RideRecord ride;

    private double latitude;
    private double longitude;
    private double speed;
    private double altitude;
    private LocalDateTime timestamp;

    /**
     * Real GPS-fix moment in epoch millis (NOT server receive time).
     * Nullable so legacy rows stay loadable; new rows always set it.
     * This is the field business code (lap detection, stats, replay)
     * should prefer for ordering and time-window matching — it survives
     * delayed delivery via BLE-backfill or MQTT-reconnect intact.
     */
    @Column(name = "captured_at_ms")
    private Long capturedAtMs;

    /** "module" | "phone" — origin of this row. Nullable for legacy. */
    @Column(name = "source", length = 16)
    private String source;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public RideRecord getRide() { return ride; }
    public void setRide(RideRecord ride) { this.ride = ride; }
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
    public Long getCapturedAtMs() { return capturedAtMs; }
    public void setCapturedAtMs(Long capturedAtMs) { this.capturedAtMs = capturedAtMs; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
}
