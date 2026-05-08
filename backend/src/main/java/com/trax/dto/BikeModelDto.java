package com.trax.dto;

public class BikeModelDto {
    private Long id;
    private String modelName;
    private String motorType;
    private String controller;
    private String imageUrl;
    private String brandName;
    private Integer motorPeakPowerW;
    private Integer motorTorqueNm;
    private String batteryType;
    private String batteryVoltage;
    private Integer batteryCapacityWh;

    public BikeModelDto() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getModelName() { return modelName; }
    public void setModelName(String modelName) { this.modelName = modelName; }
    public String getMotorType() { return motorType; }
    public void setMotorType(String motorType) { this.motorType = motorType; }
    public String getController() { return controller; }
    public void setController(String controller) { this.controller = controller; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
    public String getBrandName() { return brandName; }
    public void setBrandName(String brandName) { this.brandName = brandName; }
    public Integer getMotorPeakPowerW() { return motorPeakPowerW; }
    public void setMotorPeakPowerW(Integer motorPeakPowerW) { this.motorPeakPowerW = motorPeakPowerW; }
    public Integer getMotorTorqueNm() { return motorTorqueNm; }
    public void setMotorTorqueNm(Integer motorTorqueNm) { this.motorTorqueNm = motorTorqueNm; }
    public String getBatteryType() { return batteryType; }
    public void setBatteryType(String batteryType) { this.batteryType = batteryType; }
    public String getBatteryVoltage() { return batteryVoltage; }
    public void setBatteryVoltage(String batteryVoltage) { this.batteryVoltage = batteryVoltage; }
    public Integer getBatteryCapacityWh() { return batteryCapacityWh; }
    public void setBatteryCapacityWh(Integer batteryCapacityWh) { this.batteryCapacityWh = batteryCapacityWh; }
}
