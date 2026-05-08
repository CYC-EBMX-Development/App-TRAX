package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "ride_records")
public class RideRecord {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "trail_id")
    private Trail trail;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "bicycle_id")
    private Bicycle bicycle;

    private LocalDateTime startTime;
    private LocalDateTime endTime;
    private Double distance;
    private Double avgSpeed;
    private Double maxSpeed;
    private Double elevation;
    private String weather;
    private String status;       // active, paused, completed
    private String mode;         // with_module, without_module
    private Double totalPausedSeconds;
    private LocalDateTime lastPausedAt;

    // Lap Timer fields (only used when ride is associated with a lap-type trail)
    private Integer targetLaps;
    private Integer completedLaps;

    /** free_ride | lap_timer | race */
    private String source;

    /**
     * When true, the owner has “deleted” this ride from their own history,
     * but the underlying points/laps are kept so that other riders’ race
     * detail/replay can still display the shared path.
     */
    private Boolean hiddenByOwner;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public User getUser() { return user; }
    public void setUser(User user) { this.user = user; }
    public Trail getTrail() { return trail; }
    public void setTrail(Trail trail) { this.trail = trail; }
    public Bicycle getBicycle() { return bicycle; }
    public void setBicycle(Bicycle bicycle) { this.bicycle = bicycle; }
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
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public Integer getCompletedLaps() { return completedLaps; }
    public void setCompletedLaps(Integer completedLaps) { this.completedLaps = completedLaps; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
    public Boolean getHiddenByOwner() { return hiddenByOwner; }
    public void setHiddenByOwner(Boolean hiddenByOwner) { this.hiddenByOwner = hiddenByOwner; }
    public boolean isHiddenByOwner() { return Boolean.TRUE.equals(hiddenByOwner); }
}
