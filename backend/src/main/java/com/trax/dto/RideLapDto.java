package com.trax.dto;

import com.trax.model.RideLap;
import com.trax.model.RideLapCheckpoint;

import java.util.List;

public class RideLapDto {
    private Integer lapNumber;
    private Long durationSeconds;
    private Double distanceKm;
    private String startTime;
    private String endTime;
    private Double overlapPercent;
    private List<LapCheckpointPassDto> checkpointPasses;

    public static RideLapDto fromEntity(RideLap lap) {
        return fromEntity(lap, List.of());
    }

    public static RideLapDto fromEntity(RideLap lap, List<RideLapCheckpoint> passes) {
        RideLapDto dto = new RideLapDto();
        dto.lapNumber = lap.getLapNumber();
        dto.durationSeconds = lap.getDurationSeconds();
        dto.distanceKm = lap.getDistanceKm();
        dto.startTime = lap.getStartTime() != null ? lap.getStartTime().toString() : null;
        dto.endTime = lap.getEndTime() != null ? lap.getEndTime().toString() : null;
        dto.overlapPercent = lap.getOverlapPercent();
        dto.checkpointPasses = passes == null ? List.of()
                : passes.stream().map(p -> LapCheckpointPassDto.fromEntity(p, lap)).toList();
        return dto;
    }

    public Integer getLapNumber() { return lapNumber; }
    public void setLapNumber(Integer lapNumber) { this.lapNumber = lapNumber; }
    public Long getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(Long durationSeconds) { this.durationSeconds = durationSeconds; }
    public Double getDistanceKm() { return distanceKm; }
    public void setDistanceKm(Double distanceKm) { this.distanceKm = distanceKm; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public Double getOverlapPercent() { return overlapPercent; }
    public void setOverlapPercent(Double overlapPercent) { this.overlapPercent = overlapPercent; }
    public List<LapCheckpointPassDto> getCheckpointPasses() { return checkpointPasses; }
    public void setCheckpointPasses(List<LapCheckpointPassDto> checkpointPasses) { this.checkpointPasses = checkpointPasses; }
}
