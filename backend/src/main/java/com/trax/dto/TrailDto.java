package com.trax.dto;

import com.trax.model.Trail;
import com.trax.model.User;
import com.trax.util.AvatarUrls;

public class TrailDto {
    private Long id;
    private String name;
    private String location;
    private String difficulty;
    private boolean isPublic;
    private String description;
    private String imageUrl;
    private Double distance;
    private Double elevation;
    private Double elevationDiff;
    private String type;
    private Long creatorId;
    private String creatorName;
    private String creatorAvatarUrl;
    private Double startLatitude;
    private Double startLongitude;
    private Double endLatitude;
    private Double endLongitude;
    private String createdAt;

    public static TrailDto fromEntity(Trail t) {
        TrailDto dto = new TrailDto();
        dto.id = t.getId();
        dto.name = t.getName();
        dto.location = t.getLocation();
        dto.difficulty = t.getDifficulty();
        dto.isPublic = t.isPublic();
        dto.description = t.getDescription();
        dto.imageUrl = t.getImageUrl();
        dto.distance = t.getDistance();
        dto.elevation = t.getElevation();
        dto.elevationDiff = t.getElevationDiff();
        dto.type = t.getType();
        dto.creatorId = t.getCreatorId();
        dto.startLatitude = t.getStartLatitude();
        dto.startLongitude = t.getStartLongitude();
        dto.endLatitude = t.getEndLatitude();
        dto.endLongitude = t.getEndLongitude();
        dto.createdAt = t.getCreatedAt() != null ? t.getCreatedAt().toString() : null;
        return dto;
    }

    public static TrailDto fromEntity(Trail t, User creator) {
        TrailDto dto = fromEntity(t);
        if (creator != null) {
            dto.creatorName = creator.getName();
            dto.creatorAvatarUrl = AvatarUrls.versioned(creator);
        }
        return dto;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }
    public String getDifficulty() { return difficulty; }
    public void setDifficulty(String difficulty) { this.difficulty = difficulty; }
    public boolean isPublic() { return isPublic; }
    public void setPublic(boolean isPublic) { this.isPublic = isPublic; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
    public Double getDistance() { return distance; }
    public void setDistance(Double distance) { this.distance = distance; }
    public Double getElevation() { return elevation; }
    public void setElevation(Double elevation) { this.elevation = elevation; }
    public Double getElevationDiff() { return elevationDiff; }
    public void setElevationDiff(Double elevationDiff) { this.elevationDiff = elevationDiff; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public Long getCreatorId() { return creatorId; }
    public void setCreatorId(Long creatorId) { this.creatorId = creatorId; }
    public String getCreatorName() { return creatorName; }
    public void setCreatorName(String creatorName) { this.creatorName = creatorName; }
    public String getCreatorAvatarUrl() { return creatorAvatarUrl; }
    public void setCreatorAvatarUrl(String creatorAvatarUrl) { this.creatorAvatarUrl = creatorAvatarUrl; }
    public Double getStartLatitude() { return startLatitude; }
    public void setStartLatitude(Double startLatitude) { this.startLatitude = startLatitude; }
    public Double getStartLongitude() { return startLongitude; }
    public void setStartLongitude(Double startLongitude) { this.startLongitude = startLongitude; }
    public Double getEndLatitude() { return endLatitude; }
    public void setEndLatitude(Double endLatitude) { this.endLatitude = endLatitude; }
    public Double getEndLongitude() { return endLongitude; }
    public void setEndLongitude(Double endLongitude) { this.endLongitude = endLongitude; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
