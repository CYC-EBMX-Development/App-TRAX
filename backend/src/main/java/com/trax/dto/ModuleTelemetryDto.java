package com.trax.dto;

public class ModuleTelemetryDto {
    private String serialNo;
    private double latitude;
    private double longitude;
    /** Altitude in meters above MSL; nullable when the module did not
     *  emit altitude in this frame. */
    private Double altitude;
    private double speed;
    private int batteryPercent;
    private int signalStrength;
    /** Number of GNSS satellites currently used for the fix (SV count).
     *  Nullable when the module did not report it. */
    private Integer satellites;
    private String timestamp;

    public String getSerialNo() { return serialNo; }
    public void setSerialNo(String serialNo) { this.serialNo = serialNo; }
    public double getLatitude() { return latitude; }
    public void setLatitude(double latitude) { this.latitude = latitude; }
    public double getLongitude() { return longitude; }
    public void setLongitude(double longitude) { this.longitude = longitude; }
    public Double getAltitude() { return altitude; }
    public void setAltitude(Double altitude) { this.altitude = altitude; }
    public double getSpeed() { return speed; }
    public void setSpeed(double speed) { this.speed = speed; }
    public int getBatteryPercent() { return batteryPercent; }
    public void setBatteryPercent(int batteryPercent) { this.batteryPercent = batteryPercent; }
    public int getSignalStrength() { return signalStrength; }
    public void setSignalStrength(int signalStrength) { this.signalStrength = signalStrength; }
    public Integer getSatellites() { return satellites; }
    public void setSatellites(Integer satellites) { this.satellites = satellites; }
    public String getTimestamp() { return timestamp; }
    public void setTimestamp(String timestamp) { this.timestamp = timestamp; }
}
