package com.trax.dto;

import com.trax.model.Race;
import com.trax.model.RaceParticipant;
import com.trax.util.AvatarUrls;

import java.util.List;

public class RaceDto {
    private Long id;
    private String name;
    private Long hostId;
    private String hostName;
    private String hostAvatarUrl;
    private Long trailId;
    private String trailName;
    private Double trailDistance;
    private String scheduledTime;
    private Integer maxParticipants;
    private Integer currentParticipants;
    private Integer targetLaps;
    private boolean isPublic;
    private String notes;
    private String joinCode;
    private String status;
    private String gameType;
    private String startedAt;
    private String endedAt;
    private String createdAt;
    private List<RaceParticipantDto> participants;
    private String myRole;  // host / rider / observer / null (not joined)

    public static RaceDto fromEntity(Race r, List<RaceParticipant> participants, Long currentUserId) {
        RaceDto dto = new RaceDto();
        dto.id = r.getId();
        dto.name = r.getName();
        dto.hostId = r.getHost().getId();
        dto.hostName = r.getHost().getName();
        dto.hostAvatarUrl = AvatarUrls.versioned(r.getHost());
        dto.trailId = r.getTrail().getId();
        dto.trailName = r.getTrail().getName();
        dto.trailDistance = r.getTrail().getDistance();
        dto.scheduledTime = r.getScheduledTime() != null ? r.getScheduledTime().toString() : null;
        dto.maxParticipants = r.getMaxParticipants();
        dto.targetLaps = r.getTargetLaps();
        dto.isPublic = r.isPublic();
        dto.notes = r.getNotes();
        dto.joinCode = r.getJoinCode();
        dto.status = r.getStatus();
        dto.gameType = r.getGameType() == null ? "RACE" : r.getGameType();
        dto.startedAt = r.getStartedAt() != null ? r.getStartedAt().toString() : null;
        dto.endedAt = r.getEndedAt() != null ? r.getEndedAt().toString() : null;
        dto.createdAt = r.getCreatedAt() != null ? r.getCreatedAt().toString() : null;

        if (participants != null) {
            // Count riders only (host + rider roles)
            dto.currentParticipants = (int) participants.stream()
                    .filter(p -> "host".equals(p.getRole()) || "rider".equals(p.getRole()))
                    .count();
            dto.participants = participants.stream()
                    .map(RaceParticipantDto::fromEntity)
                    .toList();
            if (currentUserId != null) {
                dto.myRole = participants.stream()
                        .filter(p -> p.getUser().getId().equals(currentUserId))
                        .map(RaceParticipant::getRole)
                        .findFirst()
                        .orElse(null);
            }
        }
        return dto;
    }

    // ── Getters & Setters ────────────────────────────────

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public Long getHostId() { return hostId; }
    public void setHostId(Long hostId) { this.hostId = hostId; }
    public String getHostName() { return hostName; }
    public void setHostName(String hostName) { this.hostName = hostName; }
    public String getHostAvatarUrl() { return hostAvatarUrl; }
    public void setHostAvatarUrl(String hostAvatarUrl) { this.hostAvatarUrl = hostAvatarUrl; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public String getTrailName() { return trailName; }
    public void setTrailName(String trailName) { this.trailName = trailName; }
    public Double getTrailDistance() { return trailDistance; }
    public void setTrailDistance(Double trailDistance) { this.trailDistance = trailDistance; }
    public String getScheduledTime() { return scheduledTime; }
    public void setScheduledTime(String scheduledTime) { this.scheduledTime = scheduledTime; }
    public Integer getMaxParticipants() { return maxParticipants; }
    public void setMaxParticipants(Integer maxParticipants) { this.maxParticipants = maxParticipants; }
    public Integer getCurrentParticipants() { return currentParticipants; }
    public void setCurrentParticipants(Integer currentParticipants) { this.currentParticipants = currentParticipants; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public boolean isPublic() { return isPublic; }
    public void setPublic(boolean isPublic) { this.isPublic = isPublic; }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }
    public String getJoinCode() { return joinCode; }
    public void setJoinCode(String joinCode) { this.joinCode = joinCode; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getGameType() { return gameType; }
    public void setGameType(String gameType) { this.gameType = gameType; }
    public String getStartedAt() { return startedAt; }
    public void setStartedAt(String startedAt) { this.startedAt = startedAt; }
    public String getEndedAt() { return endedAt; }
    public void setEndedAt(String endedAt) { this.endedAt = endedAt; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
    public List<RaceParticipantDto> getParticipants() { return participants; }
    public void setParticipants(List<RaceParticipantDto> participants) { this.participants = participants; }
    public String getMyRole() { return myRole; }
    public void setMyRole(String myRole) { this.myRole = myRole; }
}
