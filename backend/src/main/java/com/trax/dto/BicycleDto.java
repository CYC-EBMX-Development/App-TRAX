package com.trax.dto;

import com.trax.model.Bicycle;
import java.time.LocalDateTime;

public class BicycleDto {
    private Long id;
    private String name;
    private String motor;
    private String controller;
    private String battery;
    private String other;
    private String imageUrl;
    private String traxSerialNumber;
    private boolean motorCertified;
    private boolean controllerCertified;
    private boolean batteryCertified;
    private String modelBrand;
    private String modelName;
    private LocalDateTime createdAt;
    private boolean isConnected;

    public BicycleDto() {}

    public static BicycleDto fromBicycle(Bicycle bicycle) {
        BicycleDto dto = new BicycleDto();
        dto.setId(bicycle.getId());
        dto.setName(bicycle.getName());
        dto.setMotor(bicycle.getMotor());
        dto.setController(bicycle.getController());
        dto.setBattery(bicycle.getBattery());
        dto.setOther(bicycle.getOther());
        dto.setImageUrl(bicycle.getImageUrl());
        dto.setTraxSerialNumber(bicycle.getTraxSerialNumber());
        dto.setMotorCertified(bicycle.isMotorCertified());
        dto.setControllerCertified(bicycle.isControllerCertified());
        dto.setBatteryCertified(bicycle.isBatteryCertified());
        dto.setCreatedAt(bicycle.getCreatedAt());
        dto.setIsConnected(bicycle.getTraxSerialNumber() != null && !bicycle.getTraxSerialNumber().isEmpty());

        if (bicycle.getModel() != null) {
            dto.setModelBrand(bicycle.getModel().getBrand().getName());
            dto.setModelName(bicycle.getModel().getModelName());
        }

        return dto;
    }

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getMotor() { return motor; }
    public void setMotor(String motor) { this.motor = motor; }

    public String getController() { return controller; }
    public void setController(String controller) { this.controller = controller; }

    public String getBattery() { return battery; }
    public void setBattery(String battery) { this.battery = battery; }

    public String getOther() { return other; }
    public void setOther(String other) { this.other = other; }

    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }

    public String getTraxSerialNumber() { return traxSerialNumber; }
    public void setTraxSerialNumber(String traxSerialNumber) { this.traxSerialNumber = traxSerialNumber; }

    public boolean isMotorCertified() { return motorCertified; }
    public void setMotorCertified(boolean motorCertified) { this.motorCertified = motorCertified; }

    public boolean isControllerCertified() { return controllerCertified; }
    public void setControllerCertified(boolean controllerCertified) { this.controllerCertified = controllerCertified; }

    public boolean isBatteryCertified() { return batteryCertified; }
    public void setBatteryCertified(boolean batteryCertified) { this.batteryCertified = batteryCertified; }

    public String getModelBrand() { return modelBrand; }
    public void setModelBrand(String modelBrand) { this.modelBrand = modelBrand; }

    public String getModelName() { return modelName; }
    public void setModelName(String modelName) { this.modelName = modelName; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public boolean isConnected() { return isConnected; }
    public void setIsConnected(boolean isConnected) { this.isConnected = isConnected; }
}
