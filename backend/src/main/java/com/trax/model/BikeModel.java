package com.trax.model;

import jakarta.persistence.*;

@Entity
@Table(name = "bike_model")
public class BikeModel {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "brand_id", nullable = false)
    private BikeBrand brand;

    @Column(nullable = false)
    private String modelName;

    @Column(length = 500)
    private String imageUrl;

    private String motorType;
    @Column(name = "motor_peak_power_w")
    private Integer motorPeakPowerW;
    private Integer motorTorqueNm;
    private String controller;
    private String batteryType;
    private String batteryVoltage;
    private Integer batteryCapacityWh;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public BikeBrand getBrand() { return brand; }
    public void setBrand(BikeBrand brand) { this.brand = brand; }
    public String getModelName() { return modelName; }
    public void setModelName(String modelName) { this.modelName = modelName; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
    public String getMotorType() { return motorType; }
    public void setMotorType(String motorType) { this.motorType = motorType; }
    public Integer getMotorPeakPowerW() { return motorPeakPowerW; }
    public void setMotorPeakPowerW(Integer motorPeakPowerW) { this.motorPeakPowerW = motorPeakPowerW; }
    public Integer getMotorTorqueNm() { return motorTorqueNm; }
    public void setMotorTorqueNm(Integer motorTorqueNm) { this.motorTorqueNm = motorTorqueNm; }
    public String getController() { return controller; }
    public void setController(String controller) { this.controller = controller; }
    public String getBatteryType() { return batteryType; }
    public void setBatteryType(String batteryType) { this.batteryType = batteryType; }
    public String getBatteryVoltage() { return batteryVoltage; }
    public void setBatteryVoltage(String batteryVoltage) { this.batteryVoltage = batteryVoltage; }
    public Integer getBatteryCapacityWh() { return batteryCapacityWh; }
    public void setBatteryCapacityWh(Integer batteryCapacityWh) { this.batteryCapacityWh = batteryCapacityWh; }
}
