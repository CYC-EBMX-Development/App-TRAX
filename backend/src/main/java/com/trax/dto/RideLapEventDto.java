package com.trax.dto;

/**
 * Lightweight push payload for the {@code /ws/rides/{rideId}/laps}
 * WebSocket topic. Sent every time a new lap is persisted, and once more
 * with {@code type="completed"} when the ride auto-finishes (target laps
 * reached).
 *
 * <p>Carries only the count + status — the client refetches
 * {@code GET /rides/{id}/stats} to pull full lap geometry, durations and
 * checkpoint passes. This keeps the WS payload small and ensures the
 * client renders the canonical server state.
 */
public class RideLapEventDto {
    /** "lap" (new lap persisted) or "completed" (ride auto-finished). */
    private String type;
    private Long rideId;
    /** Newly closed lap number; null for completed-only events. */
    private Integer lapNumber;
    private Integer completedLaps;
    private Integer targetLaps;
    /** Ride status at broadcast time: "active" or "completed". */
    private String status;
    /** ISO-8601 of the new lap's end_time (= crossing timestamp). */
    private String endTime;

    public RideLapEventDto() {}

    public static RideLapEventDto lap(Long rideId, int lapNumber, int completedLaps,
                                       Integer targetLaps, String status, String endTime) {
        RideLapEventDto dto = new RideLapEventDto();
        dto.type = "lap";
        dto.rideId = rideId;
        dto.lapNumber = lapNumber;
        dto.completedLaps = completedLaps;
        dto.targetLaps = targetLaps;
        dto.status = status;
        dto.endTime = endTime;
        return dto;
    }

    public static RideLapEventDto completed(Long rideId, int completedLaps,
                                             Integer targetLaps, String endTime) {
        RideLapEventDto dto = new RideLapEventDto();
        dto.type = "completed";
        dto.rideId = rideId;
        dto.completedLaps = completedLaps;
        dto.targetLaps = targetLaps;
        dto.status = "completed";
        dto.endTime = endTime;
        return dto;
    }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public Long getRideId() { return rideId; }
    public void setRideId(Long rideId) { this.rideId = rideId; }
    public Integer getLapNumber() { return lapNumber; }
    public void setLapNumber(Integer lapNumber) { this.lapNumber = lapNumber; }
    public Integer getCompletedLaps() { return completedLaps; }
    public void setCompletedLaps(Integer completedLaps) { this.completedLaps = completedLaps; }
    public Integer getTargetLaps() { return targetLaps; }
    public void setTargetLaps(Integer targetLaps) { this.targetLaps = targetLaps; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
}
