package com.trax.dto;

public class CreateRaceRequest {
    private String name;
    private Long trailId;
    private String scheduledTime;   // ISO-8601
    private Integer maxParticipants;
    private Integer targetLaps;
    private Boolean isPublic;
    private String notes;
    private Long bicycleId;         // host's bike for the race
    private String gameType;        // "RACE" | "LAPS" (default RACE)

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public String getScheduledTime() { return scheduledTime; }
    public void setScheduledTime(String scheduledTime) { this.scheduledTime = scheduledTime; }
    public Integer getMaxParticipants() { return maxParticipants; }
    public void setMaxParticipants(Integer maxParticipants) { this.maxParticipants = maxParticipants; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public Boolean getIsPublic() { return isPublic; }
    public void setIsPublic(Boolean isPublic) { this.isPublic = isPublic; }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }
    public Long getBicycleId() { return bicycleId; }
    public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    public String getGameType() { return gameType; }
    public void setGameType(String gameType) { this.gameType = gameType; }
}
