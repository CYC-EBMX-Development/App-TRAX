package com.trax.dto;

import com.trax.model.RideRecord;

public class RideRecordDto {
    private Long id;
    private Long bicycleId;
    private String bicycleName;
    private String status;
    private String mode;
    private String startTime;
    private String endTime;
    private Double distance;
    private Double avgSpeed;
    private Double maxSpeed;
    private Double elevation;
    private Long durationSeconds;
    private Long trailId;
    private String trailName;
    private Integer targetLaps;
    private Integer completedLaps;
    private Long raceId;
    private String source;
    private String gameType; // "RACE" | "LAPS" when source == "race"

    public static RideRecordDto fromEntity(RideRecord r) {
        RideRecordDto dto = new RideRecordDto();
        dto.id = r.getId();
        if (r.getBicycle() != null) {
            dto.bicycleId = r.getBicycle().getId();
            dto.bicycleName = r.getBicycle().getName();
        }
        if (r.getTrail() != null) {
            dto.trailId = r.getTrail().getId();
            dto.trailName = r.getTrail().getName();
        }
        dto.targetLaps = r.getTargetLaps();
        dto.completedLaps = r.getCompletedLaps();
        dto.source = r.getSource();
        dto.status = r.getStatus();
        dto.mode = r.getMode();
        dto.startTime = r.getStartTime() != null ? r.getStartTime().toString() : null;
        dto.endTime = r.getEndTime() != null ? r.getEndTime().toString() : null;
        dto.distance = r.getDistance();
        dto.avgSpeed = r.getAvgSpeed();
        dto.maxSpeed = r.getMaxSpeed();
        dto.elevation = r.getElevation();
        // Calculate duration excluding paused time
        if (r.getStartTime() != null && r.getEndTime() != null) {
            long totalSec = java.time.Duration.between(r.getStartTime(), r.getEndTime()).toSeconds();
            double paused = r.getTotalPausedSeconds() != null ? r.getTotalPausedSeconds() : 0;
            dto.durationSeconds = Math.max(0, totalSec - (long) paused);
        }
        return dto;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getBicycleId() { return bicycleId; }
    public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    public String getBicycleName() { return bicycleName; }
    public void setBicycleName(String bicycleName) { this.bicycleName = bicycleName; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getMode() { return mode; }
    public void setMode(String mode) { this.mode = mode; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public Double getDistance() { return distance; }
    public void setDistance(Double distance) { this.distance = distance; }
    public Double getAvgSpeed() { return avgSpeed; }
    public void setAvgSpeed(Double avgSpeed) { this.avgSpeed = avgSpeed; }
    public Double getMaxSpeed() { return maxSpeed; }
    public void setMaxSpeed(Double maxSpeed) { this.maxSpeed = maxSpeed; }
    public Double getElevation() { return elevation; }
    public void setElevation(Double elevation) { this.elevation = elevation; }
    public Long getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(Long durationSeconds) { this.durationSeconds = durationSeconds; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public String getTrailName() { return trailName; }
    public void setTrailName(String trailName) { this.trailName = trailName; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public Integer getCompletedLaps() { return completedLaps; }
    public void setCompletedLaps(Integer completedLaps) { this.completedLaps = completedLaps; }
    public Long getRaceId() { return raceId; }
    public void setRaceId(Long raceId) { this.raceId = raceId; }
    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }
    public String getGameType() { return gameType; }
    public void setGameType(String gameType) { this.gameType = gameType; }
}
