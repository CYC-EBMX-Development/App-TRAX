package com.trax.dto;

import java.util.List;

/**
 * Live race data returned during an active race.
 * Contains each rider's current position, stats, and lap breakdown.
 */
public class RaceLiveDto {
    private Long raceId;
    private String raceStatus;
    private String gameType;
    private long elapsedSeconds;
    private List<RiderLiveInfo> riders;

    public Long getRaceId() { return raceId; }
    public void setRaceId(Long raceId) { this.raceId = raceId; }
    public String getRaceStatus() { return raceStatus; }
    public void setRaceStatus(String raceStatus) { this.raceStatus = raceStatus; }
    public String getGameType() { return gameType; }
    public void setGameType(String gameType) { this.gameType = gameType; }
    public long getElapsedSeconds() { return elapsedSeconds; }
    public void setElapsedSeconds(long elapsedSeconds) { this.elapsedSeconds = elapsedSeconds; }
    public List<RiderLiveInfo> getRiders() { return riders; }
    public void setRiders(List<RiderLiveInfo> riders) { this.riders = riders; }

    public static class RiderLiveInfo {
        private Long userId;
        private String userName;
        private String userAvatarUrl;
        private Long rideId;
        private String status;       // racing, finished, dnf
        private Integer finishRank;
        private double latitude;
        private double longitude;
        private double speed;
        private double distanceKm;
        private long durationSeconds;
        private Integer completedLaps;
        private Long bestLapSeconds;
        private List<RideLapDto> laps;
        private List<PointDto> route;
        private Long bicycleId;
        private String bicycleName;
        private String bicycleImageUrl;

        public Long getUserId() { return userId; }
        public void setUserId(Long userId) { this.userId = userId; }
        public String getUserName() { return userName; }
        public void setUserName(String userName) { this.userName = userName; }
        public String getUserAvatarUrl() { return userAvatarUrl; }
        public void setUserAvatarUrl(String userAvatarUrl) { this.userAvatarUrl = userAvatarUrl; }
        public Long getRideId() { return rideId; }
        public void setRideId(Long rideId) { this.rideId = rideId; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public Integer getFinishRank() { return finishRank; }
        public void setFinishRank(Integer finishRank) { this.finishRank = finishRank; }
        public double getLatitude() { return latitude; }
        public void setLatitude(double latitude) { this.latitude = latitude; }
        public double getLongitude() { return longitude; }
        public void setLongitude(double longitude) { this.longitude = longitude; }
        public double getSpeed() { return speed; }
        public void setSpeed(double speed) { this.speed = speed; }
        public double getDistanceKm() { return distanceKm; }
        public void setDistanceKm(double distanceKm) { this.distanceKm = distanceKm; }
        public long getDurationSeconds() { return durationSeconds; }
        public void setDurationSeconds(long durationSeconds) { this.durationSeconds = durationSeconds; }
        public Integer getCompletedLaps() { return completedLaps; }
        public void setCompletedLaps(Integer completedLaps) { this.completedLaps = completedLaps; }
        public Long getBestLapSeconds() { return bestLapSeconds; }
        public void setBestLapSeconds(Long bestLapSeconds) { this.bestLapSeconds = bestLapSeconds; }
        public List<RideLapDto> getLaps() { return laps; }
        public void setLaps(List<RideLapDto> laps) { this.laps = laps; }
        public List<PointDto> getRoute() { return route; }
        public void setRoute(List<PointDto> route) { this.route = route; }
        public Long getBicycleId() { return bicycleId; }
        public void setBicycleId(Long bicycleId) { this.bicycleId = bicycleId; }
        public String getBicycleName() { return bicycleName; }
        public void setBicycleName(String bicycleName) { this.bicycleName = bicycleName; }
        public String getBicycleImageUrl() { return bicycleImageUrl; }
        public void setBicycleImageUrl(String bicycleImageUrl) { this.bicycleImageUrl = bicycleImageUrl; }
    }

    public static class PointDto {
        private double latitude;
        private double longitude;

        public PointDto() {}
        public PointDto(double latitude, double longitude) {
            this.latitude = latitude;
            this.longitude = longitude;
        }

        public double getLatitude() { return latitude; }
        public void setLatitude(double latitude) { this.latitude = latitude; }
        public double getLongitude() { return longitude; }
        public void setLongitude(double longitude) { this.longitude = longitude; }
    }
}
