package com.trax.dto;

import com.trax.model.RaceParticipant;
import com.trax.util.AvatarUrls;

public class RaceParticipantDto {
    private Long id;
    private Long userId;
    private String userName;
    private String userAvatarUrl;
    private String role;       // host, rider, observer
    private String status;     // joined, racing, finished, dnf
    private Long rideId;
    private Integer finishRank;
    private String joinedAt;
    private Long bicycleId;
    private String bicycleName;
    private String bicycleImageUrl;
    private String bicycleBrand;
    private String bicycleModel;
    private String bicycleMotor;
    private String bicycleBattery;

    public static RaceParticipantDto fromEntity(RaceParticipant p) {
        RaceParticipantDto dto = new RaceParticipantDto();
        dto.id = p.getId();
        dto.userId = p.getUser().getId();
        dto.userName = p.getUser().getName();
        dto.userAvatarUrl = AvatarUrls.versioned(p.getUser());
        dto.role = p.getRole();
        dto.status = p.getStatus();
        dto.rideId = p.getRide() != null ? p.getRide().getId() : null;
        dto.finishRank = p.getFinishRank();
        dto.joinedAt = p.getJoinedAt() != null ? p.getJoinedAt().toString() : null;
        if (p.getBicycle() != null) {
            dto.bicycleId = p.getBicycle().getId();
            dto.bicycleName = p.getBicycle().getName();
            dto.bicycleImageUrl = p.getBicycle().getImageUrl();
            dto.bicycleMotor = p.getBicycle().getMotor();
            dto.bicycleBattery = p.getBicycle().getBattery();
            if (p.getBicycle().getModel() != null) {
                dto.bicycleModel = p.getBicycle().getModel().getModelName();
                if (p.getBicycle().getModel().getBrand() != null) {
                    dto.bicycleBrand = p.getBicycle().getModel().getBrand().getName();
                }
            }
        }
        return dto;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public String getUserAvatarUrl() { return userAvatarUrl; }
    public void setUserAvatarUrl(String userAvatarUrl) { this.userAvatarUrl = userAvatarUrl; }
    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Long getRideId() { return rideId; }
    public void setRideId(Long rideId) { this.rideId = rideId; }
    public Integer getFinishRank() { return finishRank; }
    public void setFinishRank(Integer finishRank) { this.finishRank = finishRank; }
    public String getJoinedAt() { return joinedAt; }
    public void setJoinedAt(String joinedAt) { this.joinedAt = joinedAt; }
    public Long getBicycleId() { return bicycleId; }
    public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    public String getBicycleName() { return bicycleName; }
    public void setBicycleName(String bicycleName) { this.bicycleName = bicycleName; }
    public String getBicycleImageUrl() { return bicycleImageUrl; }
    public void setBicycleImageUrl(String bicycleImageUrl) { this.bicycleImageUrl = bicycleImageUrl; }
    public String getBicycleBrand() { return bicycleBrand; }
    public void setBicycleBrand(String bicycleBrand) { this.bicycleBrand = bicycleBrand; }
    public String getBicycleModel() { return bicycleModel; }
    public void setBicycleModel(String bicycleModel) { this.bicycleModel = bicycleModel; }
    public String getBicycleMotor() { return bicycleMotor; }
    public void setBicycleMotor(String bicycleMotor) { this.bicycleMotor = bicycleMotor; }
    public String getBicycleBattery() { return bicycleBattery; }
    public void setBicycleBattery(String bicycleBattery) { this.bicycleBattery = bicycleBattery; }
}
