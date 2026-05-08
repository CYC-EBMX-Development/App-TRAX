package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "history_bicycles")
public class HistoryBicycle {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long originalId;
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
    private Long ownerId;
    private Long modelId;
    private Long moduleId;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private LocalDateTime archivedAt;

    @PrePersist
    protected void onArchive() {
        archivedAt = LocalDateTime.now();
    }

    public static HistoryBicycle fromBicycle(Bicycle b) {
        HistoryBicycle h = new HistoryBicycle();
        h.originalId = b.getId();
        h.name = b.getName();
        h.motor = b.getMotor();
        h.controller = b.getController();
        h.battery = b.getBattery();
        h.other = b.getOther();
        h.imageUrl = b.getImageUrl();
        h.traxSerialNumber = b.getTraxSerialNumber();
        h.motorCertified = b.isMotorCertified();
        h.controllerCertified = b.isControllerCertified();
        h.batteryCertified = b.isBatteryCertified();
        h.ownerId = b.getOwner() != null ? b.getOwner().getId() : null;
        h.modelId = b.getModel() != null ? b.getModel().getId() : null;
        h.moduleId = b.getModule() != null ? b.getModule().getId() : null;
        h.createdAt = b.getCreatedAt();
        h.updatedAt = b.getUpdatedAt();
        return h;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getOriginalId() { return originalId; }
    public void setOriginalId(Long originalId) { this.originalId = originalId; }
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
    public Long getOwnerId() { return ownerId; }
    public void setOwnerId(Long ownerId) { this.ownerId = ownerId; }
    public Long getModelId() { return modelId; }
    public void setModelId(Long modelId) { this.modelId = modelId; }
    public Long getModuleId() { return moduleId; }
    public void setModuleId(Long moduleId) { this.moduleId = moduleId; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
    public LocalDateTime getArchivedAt() { return archivedAt; }
    public void setArchivedAt(LocalDateTime archivedAt) { this.archivedAt = archivedAt; }
}
