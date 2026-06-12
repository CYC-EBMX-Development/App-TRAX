package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * One controller-telemetry sample attached to a ride. Mirrors the
 * decoded {@code com.cyc.iot.common.model.CtrlFrame} (12 fields) but is
 * persisted into TRAX's OWN database (table {@code ride_ctrl_points}),
 * fully decoupled from the vesc-iot {@code device_ctrl_history} pipeline.
 *
 * <p>Rows are written ONLY while a ride is active and are throttled to the
 * same cadence as the GPS sampling mode for the device (1 Hz baseline,
 * 5 Hz near the finish line) — see {@code CtrlIngestService}. All metric
 * fields are nullable {@link Double} so a truncated frame stays loadable.
 */
@Entity
@Table(name = "ride_ctrl_points")
public class RideCtrlPoint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_id")
    private RideRecord ride;

    /** Controller frame moment in epoch millis (canonical ordering key). */
    @Column(name = "captured_at_ms")
    private Long capturedAtMs;

    private LocalDateTime timestamp;

    @Column(name = "temp_fet")       private Double tempFet;
    @Column(name = "temp_motor")     private Double tempMotor;
    @Column(name = "current_motor")  private Double currentMotor;
    @Column(name = "current_input")  private Double currentInput;
    /** avg_id (d-axis current); column renamed to avoid clashing with the PK. */
    @Column(name = "id_axis")        private Double idAxis;
    /** avg_iq (q-axis current). */
    @Column(name = "iq_axis")        private Double iqAxis;
    @Column(name = "duty")           private Double duty;
    @Column(name = "v_in")           private Double vin;
    @Column(name = "throttle")       private Double throttle;
    @Column(name = "regen")          private Double regen;
    @Column(name = "vd")             private Double vd;
    @Column(name = "vq")             private Double vq;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public RideRecord getRide() { return ride; }
    public void setRide(RideRecord ride) { this.ride = ride; }
    public Long getCapturedAtMs() { return capturedAtMs; }
    public void setCapturedAtMs(Long capturedAtMs) { this.capturedAtMs = capturedAtMs; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
    public Double getTempFet() { return tempFet; }
    public void setTempFet(Double tempFet) { this.tempFet = tempFet; }
    public Double getTempMotor() { return tempMotor; }
    public void setTempMotor(Double tempMotor) { this.tempMotor = tempMotor; }
    public Double getCurrentMotor() { return currentMotor; }
    public void setCurrentMotor(Double currentMotor) { this.currentMotor = currentMotor; }
    public Double getCurrentInput() { return currentInput; }
    public void setCurrentInput(Double currentInput) { this.currentInput = currentInput; }
    public Double getIdAxis() { return idAxis; }
    public void setIdAxis(Double idAxis) { this.idAxis = idAxis; }
    public Double getIqAxis() { return iqAxis; }
    public void setIqAxis(Double iqAxis) { this.iqAxis = iqAxis; }
    public Double getDuty() { return duty; }
    public void setDuty(Double duty) { this.duty = duty; }
    public Double getVin() { return vin; }
    public void setVin(Double vin) { this.vin = vin; }
    public Double getThrottle() { return throttle; }
    public void setThrottle(Double throttle) { this.throttle = throttle; }
    public Double getRegen() { return regen; }
    public void setRegen(Double regen) { this.regen = regen; }
    public Double getVd() { return vd; }
    public void setVd(Double vd) { this.vd = vd; }
    public Double getVq() { return vq; }
    public void setVq(Double vq) { this.vq = vq; }
}
