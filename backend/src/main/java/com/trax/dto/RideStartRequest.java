package com.trax.dto;

public class RideStartRequest {
    private Long bicycleId;
    private String mode; // with_module, without_module
    private Long trailId;        // optional, for Lap Timer rides
    private Integer targetLaps;  // optional, for Lap Timer rides

    public Long getBicycleId() { return bicycleId; }
    public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
    public String getMode() { return mode; }
    public void setMode(String mode) { this.mode = mode; }
    public Long getTrailId() { return trailId; }
    public void setTrailId(Long trailId) { this.trailId = trailId; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
}
