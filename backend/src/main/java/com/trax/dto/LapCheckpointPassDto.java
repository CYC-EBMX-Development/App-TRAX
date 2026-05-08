package com.trax.dto;

import com.trax.model.RideLap;
import com.trax.model.RideLapCheckpoint;

import java.time.Duration;
import java.time.LocalDateTime;

public class LapCheckpointPassDto {
    private Integer sequenceIndex;
    private String passTime;
    private Long secondsFromLapStart;
    private Double latitude;
    private Double longitude;

    public static LapCheckpointPassDto fromEntity(RideLapCheckpoint cp, RideLap lap) {
        LapCheckpointPassDto dto = new LapCheckpointPassDto();
        dto.sequenceIndex = cp.getSequenceIndex();
        dto.passTime = cp.getPassTime() != null ? cp.getPassTime().toString() : null;
        if (cp.getPassTime() != null && lap != null && lap.getStartTime() != null) {
            LocalDateTime start = lap.getStartTime();
            dto.secondsFromLapStart = Duration.between(start, cp.getPassTime()).toSeconds();
        }
        dto.latitude = cp.getLatitude();
        dto.longitude = cp.getLongitude();
        return dto;
    }

    public Integer getSequenceIndex() { return sequenceIndex; }
    public void setSequenceIndex(Integer sequenceIndex) { this.sequenceIndex = sequenceIndex; }
    public String getPassTime() { return passTime; }
    public void setPassTime(String passTime) { this.passTime = passTime; }
    public Long getSecondsFromLapStart() { return secondsFromLapStart; }
    public void setSecondsFromLapStart(Long secondsFromLapStart) { this.secondsFromLapStart = secondsFromLapStart; }
    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }
    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }
}
