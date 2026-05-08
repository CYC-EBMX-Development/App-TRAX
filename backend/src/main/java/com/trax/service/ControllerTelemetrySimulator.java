package com.trax.service;

import com.trax.model.BikeModel;
import com.trax.model.Bicycle;
import com.trax.model.ControllerTelemetry;
import com.trax.model.RidePoint;
import com.trax.model.RideRecord;
import com.trax.model.TraxModule;
import com.trax.repository.ControllerTelemetryRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Generates one {@link ControllerTelemetry} packet per simulator tick.
 *
 * <p>Inputs are (a) the bike's published performance (peak power, voltage,
 * battery capacity, torque) and (b) the current speed produced by the GPS
 * simulator; outputs are physically-consistent values for all 26 channels
 * the real TRAX module reads off the controller bus.
 *
 * <p>A small amount of per-ride cumulative state (odometer / Ah / Wh / trip
 * time / battery SoC) is kept in memory and reset when the ride starts.
 */
@Service
public class ControllerTelemetrySimulator {

    private static final double DEFAULT_PEAK_POWER_W = 6000.0;     // Sur-Ron Light Bee class
    private static final double DEFAULT_VOLTAGE_V    = 60.0;
    private static final double DEFAULT_CAPACITY_WH  = 1800.0;
    private static final double DEFAULT_TORQUE_NM    = 250.0;       // wheel-side
    private static final double V_MAX_KMH            = 90.0;        // for duty mapping
    private static final double WHEEL_DIAM_M         = 0.66;        // 19" rim w/ tire
    private static final double GEAR_RATIO           = 8.0;         // motor:wheel

    private final ControllerTelemetryRepository repo;

    /** Per-ride cumulative state: [odoM, ampHours, wattHours, tripTimeS,
     *                              batterySocFraction, fetTempC, motorTempC,
     *                              encoderAngleRad, prevSpeedKmh]. */
    private final Map<Long, double[]> rideState = new ConcurrentHashMap<>();

    public ControllerTelemetrySimulator(ControllerTelemetryRepository repo) {
        this.repo = repo;
    }

    public void resetRide(Long rideId) {
        if (rideId != null) rideState.remove(rideId);
    }

    /**
     * Simulate one packet and persist it.
     *
     * @param ride        owning ride (must be loaded; can be null for ghosts)
     * @param ridePoint   matching ride point (provides the canonical timestamp)
     * @param module      reporting TRAX module (may be null for race-sim ghosts)
     * @param speedKmh    current GPS-derived speed
     * @param tickSeconds seconds elapsed since the previous tick (== 1.0)
     * @param raceMode    true if the ride is part of a Race (rs_mode = 1)
     */
    public ControllerTelemetry simulateAndPersist(RideRecord ride,
                                                  RidePoint ridePoint,
                                                  TraxModule module,
                                                  double speedKmh,
                                                  double tickSeconds,
                                                  boolean raceMode) {
        if (ride == null || ridePoint == null) return null;

        BikePerf perf = resolvePerf(ride.getBicycle());

        double[] st = rideState.computeIfAbsent(ride.getId(), k -> new double[]{
                0.0,    // 0 odoM
                0.0,    // 1 ampHours
                0.0,    // 2 wattHours
                0.0,    // 3 tripTimeS
                1.0,    // 4 SoC fraction (1.0 = full)
                30.0,   // 5 fetTempC ambient
                30.0,   // 6 motorTempC ambient
                0.0,    // 7 encoder angle rad
                0.0     // 8 prev speed km/h
        });

        ThreadLocalRandom rnd = ThreadLocalRandom.current();
        double v = Math.max(0.0, speedKmh);
        double prevV = st[8];

        // ---- duty cycle, RPM ------------------------------------------------
        double duty = clamp(v / V_MAX_KMH, 0.0, 1.0);
        // wheel rev/s = v(km/h) / 3.6 / (π·D) ; motor rpm = wheelRev * gear * 60
        double wheelRevPerS = (v / 3.6) / (Math.PI * WHEEL_DIAM_M);
        double motorRpm = wheelRevPerS * GEAR_RATIO * 60.0;

        // ---- battery voltage sag with load + SoC droop ---------------------
        double socDroopV   = perf.voltageV * (1.0 - st[4]) * 0.18;          // 18% droop @ empty
        double loadSagV    = perf.voltageV * 0.05 * duty;
        double inputV = perf.voltageV - socDroopV - loadSagV
                + rnd.nextGaussian() * 0.05;
        inputV = Math.max(perf.voltageV * 0.6, inputV);

        // ---- electrical power & currents -----------------------------------
        // power roughly ~ peak * duty^1.5 (acceleration draws more than steady)
        double accel = (v - prevV) / Math.max(0.001, tickSeconds);          // km/h per s
        double accelBoost = clamp(accel / 10.0, 0.0, 1.0) * 0.4;
        double powerW = perf.peakPowerW * Math.pow(duty, 1.5) * (0.5 + accelBoost);
        if (v < 0.5) powerW = perf.peakPowerW * 0.01;                       // idle quiescent

        double inputCurrentA = powerW / Math.max(1.0, inputV);
        double motorCurrentA = inputCurrentA / Math.max(0.05, duty);
        double iqA = motorCurrentA * 0.97 + rnd.nextGaussian() * 0.5;
        double idA = rnd.nextGaussian() * 1.5;                               // FOC d≈0
        double vqV = inputV * duty * 0.95 + rnd.nextGaussian() * 0.1;
        double vdV = rnd.nextGaussian() * 0.4;

        // ---- thermals (first-order: heat in, slow cooling) -----------------
        double heatIn   = (powerW / perf.peakPowerW) * 0.6;                  // °C/s @ peak
        double cooling  = 0.04 * (st[5] - 30.0);
        st[5] = clamp(st[5] + (heatIn - cooling) * tickSeconds, 28.0, 110.0);
        cooling         = 0.025 * (st[6] - 30.0);
        st[6] = clamp(st[6] + (heatIn * 1.2 - cooling) * tickSeconds, 28.0, 130.0);
        double fetT     = st[5] + rnd.nextGaussian() * 0.3;
        double motorT   = st[6] + rnd.nextGaussian() * 0.3;
        double[] ntc = {
                fetT + rnd.nextGaussian() * 0.5,
                fetT + rnd.nextGaussian() * 0.5,
                fetT + rnd.nextGaussian() * 0.5
        };

        // ---- encoder sin/cos (1.65V centre, 1.4V swing) --------------------
        st[7] = (st[7] + motorRpm / 60.0 * 2.0 * Math.PI * tickSeconds) % (2 * Math.PI);
        double encSin = 1.65 + 1.4 * Math.sin(st[7]);
        double encCos = 1.65 + 1.4 * Math.cos(st[7]);

        // ---- ADCs ----------------------------------------------------------
        double throttleV = 0.85 + 3.45 * duty + rnd.nextGaussian() * 0.01;
        double regenV    = 0.82 + (accel < -2 ? 1.5 * Math.min(1.0, -accel / 6.0) : 0.0)
                + rnd.nextGaussian() * 0.01;

        // ---- cumulative integrators ---------------------------------------
        double distM = (v / 3.6) * tickSeconds;
        st[0] += distM;                                                      // odo
        double dAh = (inputCurrentA * tickSeconds) / 3600.0;
        st[1] += dAh;
        double dWh = (powerW * tickSeconds) / 3600.0;
        st[2] += dWh;
        st[3] += tickSeconds;
        st[4] = clamp(st[4] - dWh / Math.max(1.0, perf.capacityWh), 0.05, 1.0);
        st[8] = v;

        // ---- assemble packet ----------------------------------------------
        ControllerTelemetry ct = new ControllerTelemetry();
        ct.setRide(ride);
        ct.setRidePoint(ridePoint);
        ct.setModule(module);
        ct.setTimestamp(ridePoint.getTimestamp() != null
                ? ridePoint.getTimestamp() : LocalDateTime.now());

        ct.setFetTempC(round1(fetT));
        ct.setMotorTempC(round1(motorT));
        ct.setAvgMotorCurrentA(round2(motorCurrentA));
        ct.setAvgInputCurrentA(round2(inputCurrentA));
        ct.setAvgIdA(round2(idA));
        ct.setAvgIqA(round2(iqA));
        ct.setDutyCycle(round3(duty));
        ct.setMotorRpm(round1(motorRpm));
        ct.setInputVoltageV(round1(inputV));
        ct.setAmpHoursAh(round4(st[1]));
        ct.setTripTimeS(round1(st[3]));
        ct.setWattHoursWh(round4(st[2]));
        ct.setEncoderSinV(round3(encSin));
        ct.setThrottleAdcV(round3(throttleV));
        ct.setRegenAdcV(round3(regenV));
        ct.setFaultCode(0);
        // bit0 = brake, bit1 = kill, bit2 = side stand etc. (idle = 0x00)
        ct.setDigitalInputState(0);
        ct.setControllerId(1);
        ct.setNtcMosTempA(round1(ntc[0]));
        ct.setNtcMosTempB(round1(ntc[1]));
        ct.setNtcMosTempC(round1(ntc[2]));
        ct.setAvgVdV(round3(vdV));
        ct.setAvgVqV(round3(vqV));
        ct.setOdometerM(Math.round(st[0]));
        ct.setEncoderCosV(round3(encCos));
        ct.setSpeedKmh(round2(v));
        ct.setRsMode(raceMode ? 1 : 0);
        ct.setAssistLevel(raceMode ? 5 : 3);

        try {
            return repo.save(ct);
        } catch (Exception e) {
            // Don't break the tick loop if persistence transiently fails.
            System.err.println("ControllerTelemetry save failed: " + e.getMessage());
            return null;
        }
    }

    // --- helpers ------------------------------------------------------------

    private BikePerf resolvePerf(Bicycle bike) {
        if (bike == null || bike.getModel() == null) return BikePerf.defaults();
        BikeModel m = bike.getModel();
        double power = m.getMotorPeakPowerW() != null && m.getMotorPeakPowerW() > 0
                ? m.getMotorPeakPowerW() : DEFAULT_PEAK_POWER_W;
        double voltage = parseVoltage(m.getBatteryVoltage());
        double capacity = m.getBatteryCapacityWh() != null && m.getBatteryCapacityWh() > 0
                ? m.getBatteryCapacityWh() : DEFAULT_CAPACITY_WH;
        double torque = m.getMotorTorqueNm() != null && m.getMotorTorqueNm() > 0
                ? m.getMotorTorqueNm() : DEFAULT_TORQUE_NM;
        return new BikePerf(power, voltage, capacity, torque);
    }

    private static double parseVoltage(String s) {
        if (s == null) return DEFAULT_VOLTAGE_V;
        StringBuilder num = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (Character.isDigit(c) || c == '.') num.append(c);
            else if (num.length() > 0) break;
        }
        if (num.length() == 0) return DEFAULT_VOLTAGE_V;
        try { return Double.parseDouble(num.toString()); }
        catch (NumberFormatException e) { return DEFAULT_VOLTAGE_V; }
    }

    private static double clamp(double v, double lo, double hi) {
        return Math.max(lo, Math.min(hi, v));
    }
    private static double round1(double v) { return Math.round(v * 10.0) / 10.0; }
    private static double round2(double v) { return Math.round(v * 100.0) / 100.0; }
    private static double round3(double v) { return Math.round(v * 1000.0) / 1000.0; }
    private static double round4(double v) { return Math.round(v * 10000.0) / 10000.0; }

    private record BikePerf(double peakPowerW, double voltageV,
                            double capacityWh, double torqueNm) {
        static BikePerf defaults() {
            return new BikePerf(DEFAULT_PEAK_POWER_W, DEFAULT_VOLTAGE_V,
                    DEFAULT_CAPACITY_WH, DEFAULT_TORQUE_NM);
        }
    }
}
