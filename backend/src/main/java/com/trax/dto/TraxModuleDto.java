package com.trax.dto;

public class TraxModuleDto {
    private String serialNo;
    private String name;
    private boolean bound;

    // Bike spec fields (null when no spec is linked)
    private String motor;
    private String controller;
    private String battery;
    private boolean motorCertified;
    private boolean controllerCertified;
    private boolean batteryCertified;

    // Model info
    private String modelBrand;
    private String modelName;

    public TraxModuleDto() {}

    public String getSerialNo() { return serialNo; }
    public void setSerialNo(String serialNo) { this.serialNo = serialNo; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public boolean isBound() { return bound; }
    public void setBound(boolean bound) { this.bound = bound; }
    public String getMotor() { return motor; }
    public void setMotor(String motor) { this.motor = motor; }
    public String getController() { return controller; }
    public void setController(String controller) { this.controller = controller; }
    public String getBattery() { return battery; }
    public void setBattery(String battery) { this.battery = battery; }
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
}

