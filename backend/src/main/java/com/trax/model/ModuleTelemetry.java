package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "module_telemetry",
        uniqueConstraints = @UniqueConstraint(
                name = "ux_module_telemetry_module_ts",
                columnNames = {"module_id", "timestamp_millis"}))
public class ModuleTelemetry {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "module_id")
    private TraxModule module;

    private double latitude;
    private double longitude;
    /** Altitude in meters above MSL as reported by the module GNSS chip.
     *  Nullable for legacy rows / live frames that lack altitude. */
    private Double altitude;
    private double speed;
    private int batteryPercent;
    private int signalStrength;
    /** Number of GNSS satellites currently used for the fix (SV count),
     *  as reported by the module in the $PCYCGPS sentence. Nullable for
     *  legacy rows / frames that predate satellite reporting. */
    private Integer satellites;
    private LocalDateTime timestamp;

    /** Module-side timestamp in epoch millis. Source of truth for dedup;
     *  the same frame can arrive via MQTT and via the App's BLE relay and
     *  must be stored exactly once.  Nullable for legacy rows. */
    @Column(name = "timestamp_millis")
    private Long timestampMillis;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public TraxModule getModule() { return module; }
    public void setModule(TraxModule module) { this.module = module; }
    public double getLatitude() { return latitude; }
    public void setLatitude(double latitude) { this.latitude = latitude; }
    public double getLongitude() { return longitude; }
    public void setLongitude(double longitude) { this.longitude = longitude; }
    public Double getAltitude() { return altitude; }
    public void setAltitude(Double altitude) { this.altitude = altitude; }
    public double getSpeed() { return speed; }
    public void setSpeed(double speed) { this.speed = speed; }
    public int getBatteryPercent() { return batteryPercent; }
    public void setBatteryPercent(int batteryPercent) { this.batteryPercent = batteryPercent; }
    public int getSignalStrength() { return signalStrength; }
    public void setSignalStrength(int signalStrength) { this.signalStrength = signalStrength; }
    public Integer getSatellites() { return satellites; }
    public void setSatellites(Integer satellites) { this.satellites = satellites; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
    public Long getTimestampMillis() { return timestampMillis; }
    public void setTimestampMillis(Long timestampMillis) { this.timestampMillis = timestampMillis; }
}
