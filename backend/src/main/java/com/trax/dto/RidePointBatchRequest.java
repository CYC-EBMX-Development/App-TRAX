package com.trax.dto;

import java.util.List;

public class RidePointBatchRequest {
    private List<RidePointDto> points;

    public List<RidePointDto> getPoints() { return points; }
    public void setPoints(List<RidePointDto> points) { this.points = points; }
}
