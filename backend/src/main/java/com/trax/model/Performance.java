package com.trax.model;

import jakarta.persistence.*;

@Entity
@Table(name = "performances")
public class Performance {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "trail_id")
    private Trail trail;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_record_id")
    private RideRecord rideRecord;

    private Double bestTime;
    private Double bestSpeed;
    private String weather;
    private String ebikeInfo;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public User getUser() { return user; }
    public void setUser(User user) { this.user = user; }
    public Trail getTrail() { return trail; }
    public void setTrail(Trail trail) { this.trail = trail; }
    public RideRecord getRideRecord() { return rideRecord; }
    public void setRideRecord(RideRecord rideRecord) { this.rideRecord = rideRecord; }
    public Double getBestTime() { return bestTime; }
    public void setBestTime(Double bestTime) { this.bestTime = bestTime; }
    public Double getBestSpeed() { return bestSpeed; }
    public void setBestSpeed(Double bestSpeed) { this.bestSpeed = bestSpeed; }
    public String getWeather() { return weather; }
    public void setWeather(String weather) { this.weather = weather; }
    public String getEbikeInfo() { return ebikeInfo; }
    public void setEbikeInfo(String ebikeInfo) { this.ebikeInfo = ebikeInfo; }
}
