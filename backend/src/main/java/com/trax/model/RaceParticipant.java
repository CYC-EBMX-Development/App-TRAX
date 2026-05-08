package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "race_participants",
       uniqueConstraints = @UniqueConstraint(columnNames = {"race_id", "user_id"}))
public class RaceParticipant {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "race_id", nullable = false)
    private Race race;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    /** host | rider | observer */
    @Column(nullable = false)
    private String role;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_id")
    private RideRecord ride;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "bicycle_id")
    private Bicycle bicycle;

    private LocalDateTime joinedAt;

    /** joined | ready | racing | finished | dnf */
    @Column(nullable = false)
    private String status;

    /** Finishing rank (1 = first, null = not finished) */
    private Integer finishRank;

    /** Best single-lap duration in seconds (LAPS mode ranking) */
    @Column(name = "best_lap_seconds")
    private Long bestLapSeconds;

    /** Rider GPS position (used during preparing phase) */
    private Double latitude;
    private Double longitude;

    @PrePersist
    protected void onCreate() {
        joinedAt = LocalDateTime.now();
        if (status == null) status = "joined";
    }

    // ── Getters & Setters ────────────────────────────────

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Race getRace() { return race; }
    public void setRace(Race race) { this.race = race; }

    public User getUser() { return user; }
    public void setUser(User user) { this.user = user; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public RideRecord getRide() { return ride; }
    public void setRide(RideRecord ride) { this.ride = ride; }

    public LocalDateTime getJoinedAt() { return joinedAt; }
    public void setJoinedAt(LocalDateTime joinedAt) { this.joinedAt = joinedAt; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public Integer getFinishRank() { return finishRank; }
    public void setFinishRank(Integer finishRank) { this.finishRank = finishRank; }

    public Long getBestLapSeconds() { return bestLapSeconds; }
    public void setBestLapSeconds(Long bestLapSeconds) { this.bestLapSeconds = bestLapSeconds; }

    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }

    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }

    public Bicycle getBicycle() { return bicycle; }
    public void setBicycle(Bicycle bicycle) { this.bicycle = bicycle; }
}
