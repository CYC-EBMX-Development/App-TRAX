package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "bicycles")
public class Bicycle {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    private String motor;
    private String controller;
    private String battery;
    private String other;
    private String imageUrl;

    // Cached SN of the bound TRA-X module. NULL == unbound. Unique so that at
    // most one bicycle (across the whole system, any user) can claim a given
    // serial — defence-in-depth on top of the service-level isBound() guard.
    // Most DBs (MySQL/Postgres/H2) treat NULL values as distinct in unique
    // indexes, so multiple unbound bikes coexist without violating this.
    @Column(name = "trax_serial_number", unique = true)
    private String traxSerialNumber;

    private boolean motorCertified;
    private boolean controllerCertified;
    private boolean batteryCertified;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "owner_id", nullable = false)
    private User owner;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "model_id")
    private BikeModel model;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "module_id")
    private TraxModule module;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
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

    public User getOwner() { return owner; }
    public void setOwner(User owner) { this.owner = owner; }

    public BikeModel getModel() { return model; }
    public void setModel(BikeModel model) { this.model = model; }

    public TraxModule getModule() { return module; }
    public void setModule(TraxModule module) { this.module = module; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
}
