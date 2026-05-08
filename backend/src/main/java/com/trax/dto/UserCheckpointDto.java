package com.trax.dto;

import com.trax.model.UserCheckpoint;

public class UserCheckpointDto {
    private Long id;
    private Long trailId;
    private Integer sequenceIndex;
    private Double latitude;
    private Double longitude;

    public static UserCheckpointDto fromEntity(UserCheckpoint cp) {
        UserCheckpointDto dto = new UserCheckpointDto();
        dto.id = cp.getId();
        dto.trailId = cp.getTrail() != null ? cp.getTrail().getId() : null;
        dto.sequenceIndex = cp.getSequenceIndex();
        dto.latitude = cp.getLatitude();
        dto.longitude = cp.getLongitude();
        return dto;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public Integer getSequenceIndex() { return sequenceIndex; }
    public void setSequenceIndex(Integer sequenceIndex) { this.sequenceIndex = sequenceIndex; }
    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }
    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }
}
