package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Per-second snapshot of the e-motorcycle motor controller (VESC-style) data
 * read by the TRAX module over CAN/UART. All 26 channels in the module's
 * upstream packet are captured here. One row corresponds to one upload tick
 * (1 Hz) and is time-aligned with the matching {@link RidePoint}.
 */
@Entity
@Table(name = "controller_telemetry", indexes = {
        @Index(name = "idx_ctrl_tel_ride", columnList = "ride_id"),
        @Index(name = "idx_ctrl_tel_ts", columnList = "timestamp")
})
public class ControllerTelemetry {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_id")
    private RideRecord ride;

    /** Optional 1:1 link to the matching ride point (same timestamp). */
    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ride_point_id")
    private RidePoint ridePoint;

    /** Module that produced this packet (null for race-sim ghost riders). */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "module_id")
    private TraxModule module;

    /** Server-side receive timestamp (== ridePoint.timestamp for sim'd data). */
    private LocalDateTime timestamp;

    // ----------------------------------------------------------------------
    // 26-bit controller payload (units stored in human-friendly SI form)
    // ----------------------------------------------------------------------

    /** Bit 0  - mc_interface_temp_fet_filtered  [°C] */
    private Double fetTempC;
    /** Bit 1  - mc_interface_temp_motor_filtered  [°C] */
    private Double motorTempC;
    /** Bit 2  - mc_interface_read_reset_avg_motor_current  [A] */
    private Double avgMotorCurrentA;
    /** Bit 3  - mc_interface_read_reset_avg_input_current  [A] */
    private Double avgInputCurrentA;
    /** Bit 4  - mc_interface_read_reset_avg_id  [A]  (FOC d-axis) */
    private Double avgIdA;
    /** Bit 5  - mc_interface_read_reset_avg_iq  [A]  (FOC q-axis) */
    private Double avgIqA;
    /** Bit 6  - mc_interface_get_duty_cycle_now  [0..1] */
    private Double dutyCycle;
    /** Bit 7  - mc_interface_get_actual_rpm  [RPM] */
    private Double motorRpm;
    /** Bit 8  - mc_interface_get_input_voltage_filtered  [V] */
    private Double inputVoltageV;
    /** Bit 9  - mc_interface_get_amp_hours(false)  [Ah] - cumulative */
    private Double ampHoursAh;
    /** Bit 10 - app_get_total_tt  [s] - cumulative trip time */
    private Double tripTimeS;
    /** Bit 11 - mc_interface_get_watt_hours(false)  [Wh] - cumulative */
    private Double wattHoursWh;
    /** Bit 12 - ENCODER_SIN_VOLTS  [V] */
    private Double encoderSinV;
    /** Bit 13 - app_adc_get_voltage  [V]  (Throttle ADC) */
    private Double throttleAdcV;
    /** Bit 14 - app_adc_get_voltage2 [V]  (Regen ADC) */
    private Double regenAdcV;
    /** Bit 15 - mc_interface_get_fault  (enum int code, 0 = no fault) */
    private Integer faultCode;
    /** Bit 16 - 8 digital input pin states packed into low byte */
    private Integer digitalInputState;
    /** Bit 17 - controller_id  (1 = primary motor) */
    private Integer controllerId;
    /** Bit 18a - NTC_TEMP_MOS1  [°C] */
    private Double ntcMosTempA;
    /** Bit 18b - NTC_TEMP_MOS2  [°C] */
    private Double ntcMosTempB;
    /** Bit 18c - NTC_TEMP_MOS3  [°C] */
    private Double ntcMosTempC;
    /** Bit 19 - mc_interface_read_reset_avg_vd  [V] */
    private Double avgVdV;
    /** Bit 20 - mc_interface_read_reset_avg_vq  [V] */
    private Double avgVqV;
    /** Bit 21 - app_get_odo  [m] - cumulative odometer */
    private Long odometerM;
    /** Bit 22 - ENCODER_COS_VOLTS  [V] */
    private Double encoderCosV;
    /** Bit 23 - app_get_speed_km_r  [km/h] */
    private Double speedKmh;
    /** Bit 24 - app_get_rs_mode  (0 = Street, 1 = Race) */
    private Integer rsMode;
    /** Bit 25 - app_get_assis_lv  (assist level 0..5) */
    private Integer assistLevel;

    // ----------------------------------------------------------------------
    // Boilerplate getters / setters
    // ----------------------------------------------------------------------
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public RideRecord getRide() { return ride; }
    public void setRide(RideRecord ride) { this.ride = ride; }
    public RidePoint getRidePoint() { return ridePoint; }
    public void setRidePoint(RidePoint ridePoint) { this.ridePoint = ridePoint; }
    public TraxModule getModule() { return module; }
    public void setModule(TraxModule module) { this.module = module; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
    public Double getFetTempC() { return fetTempC; }
    public void setFetTempC(Double v) { this.fetTempC = v; }
    public Double getMotorTempC() { return motorTempC; }
    public void setMotorTempC(Double v) { this.motorTempC = v; }
    public Double getAvgMotorCurrentA() { return avgMotorCurrentA; }
    public void setAvgMotorCurrentA(Double v) { this.avgMotorCurrentA = v; }
    public Double getAvgInputCurrentA() { return avgInputCurrentA; }
    public void setAvgInputCurrentA(Double v) { this.avgInputCurrentA = v; }
    public Double getAvgIdA() { return avgIdA; }
    public void setAvgIdA(Double v) { this.avgIdA = v; }
    public Double getAvgIqA() { return avgIqA; }
    public void setAvgIqA(Double v) { this.avgIqA = v; }
    public Double getDutyCycle() { return dutyCycle; }
    public void setDutyCycle(Double v) { this.dutyCycle = v; }
    public Double getMotorRpm() { return motorRpm; }
    public void setMotorRpm(Double v) { this.motorRpm = v; }
    public Double getInputVoltageV() { return inputVoltageV; }
    public void setInputVoltageV(Double v) { this.inputVoltageV = v; }
    public Double getAmpHoursAh() { return ampHoursAh; }
    public void setAmpHoursAh(Double v) { this.ampHoursAh = v; }
    public Double getTripTimeS() { return tripTimeS; }
    public void setTripTimeS(Double v) { this.tripTimeS = v; }
    public Double getWattHoursWh() { return wattHoursWh; }
    public void setWattHoursWh(Double v) { this.wattHoursWh = v; }
    public Double getEncoderSinV() { return encoderSinV; }
    public void setEncoderSinV(Double v) { this.encoderSinV = v; }
    public Double getThrottleAdcV() { return throttleAdcV; }
    public void setThrottleAdcV(Double v) { this.throttleAdcV = v; }
    public Double getRegenAdcV() { return regenAdcV; }
    public void setRegenAdcV(Double v) { this.regenAdcV = v; }
    public Integer getFaultCode() { return faultCode; }
    public void setFaultCode(Integer v) { this.faultCode = v; }
    public Integer getDigitalInputState() { return digitalInputState; }
    public void setDigitalInputState(Integer v) { this.digitalInputState = v; }
    public Integer getControllerId() { return controllerId; }
    public void setControllerId(Integer v) { this.controllerId = v; }
    public Double getNtcMosTempA() { return ntcMosTempA; }
    public void setNtcMosTempA(Double v) { this.ntcMosTempA = v; }
    public Double getNtcMosTempB() { return ntcMosTempB; }
    public void setNtcMosTempB(Double v) { this.ntcMosTempB = v; }
    public Double getNtcMosTempC() { return ntcMosTempC; }
    public void setNtcMosTempC(Double v) { this.ntcMosTempC = v; }
    public Double getAvgVdV() { return avgVdV; }
    public void setAvgVdV(Double v) { this.avgVdV = v; }
    public Double getAvgVqV() { return avgVqV; }
    public void setAvgVqV(Double v) { this.avgVqV = v; }
    public Long getOdometerM() { return odometerM; }
    public void setOdometerM(Long v) { this.odometerM = v; }
    public Double getEncoderCosV() { return encoderCosV; }
    public void setEncoderCosV(Double v) { this.encoderCosV = v; }
    public Double getSpeedKmh() { return speedKmh; }
    public void setSpeedKmh(Double v) { this.speedKmh = v; }
    public Integer getRsMode() { return rsMode; }
    public void setRsMode(Integer v) { this.rsMode = v; }
    public Integer getAssistLevel() { return assistLevel; }
    public void setAssistLevel(Integer v) { this.assistLevel = v; }
}
