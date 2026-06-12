package com.trax.service;

import com.cyc.iot.common.codec.NmeaGpsCodec;
import com.cyc.iot.common.model.GpsFrame;
import com.trax.dto.ModuleTelemetryDto;
import com.trax.model.ModuleTelemetry;
import com.trax.model.RidePoint;
import com.trax.model.TraxModule;
import com.trax.repository.ModuleTelemetryRepository;
import com.trax.repository.TraxModuleRepository;
import com.trax.signal.LocationIngestService;
import com.trax.signal.ModuleNmeaAdapter;
import com.trax.signal.ModuleSamplingCoordinator;
import com.trax.signal.UnifiedLocationFrame;
import com.trax.websocket.ModuleTelemetryWebSocketHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Service
public class ModuleTelemetryService {
    private static final Logger log = LoggerFactory.getLogger(ModuleTelemetryService.class);

    private final ModuleTelemetryRepository telemetryRepository;
    private final TraxModuleRepository moduleRepository;
    private final LocationIngestService locationIngestService;

    /** Optional — only present when the WebSocket auto-config is active. */
    @Autowired(required = false)
    private ModuleTelemetryWebSocketHandler wsHandler;

    /** Backend-driven module GPS sampling-rate control (finish-line 5 Hz
     *  densification, 1 Hz otherwise). Always present. */
    @Autowired
    private ModuleSamplingCoordinator samplingCoordinator;

    /** Lazy to avoid a circular bean graph in tests; in production this is
     *  always resolved before the first MQTT frame arrives. */
    @Autowired
    @Lazy
    private RideService rideService;

    public ModuleTelemetryService(ModuleTelemetryRepository telemetryRepository,
                                  TraxModuleRepository moduleRepository,
                                  LocationIngestService locationIngestService) {
        this.telemetryRepository = telemetryRepository;
        this.moduleRepository = moduleRepository;
        this.locationIngestService = locationIngestService;
    }

    /**
     * Manual record (used by the legacy REST endpoint and by the App when
     * pushing data sources it has already decoded). Always records;
     * timestamp comes from server clock so dedup does not apply.
     */
    public ModuleTelemetryDto recordTelemetry(String serialNo, ModuleTelemetryDto dto) {
        TraxModule module = moduleRepository.findBySerialNo(serialNo)
                .orElseThrow(() -> new IllegalArgumentException("Module not found: " + serialNo));

        ModuleTelemetry t = new ModuleTelemetry();
        t.setModule(module);
        t.setLatitude(dto.getLatitude());
        t.setLongitude(dto.getLongitude());
        t.setAltitude(dto.getAltitude());
        t.setSpeed(dto.getSpeed());
        t.setBatteryPercent(dto.getBatteryPercent());
        t.setSignalStrength(dto.getSignalStrength());
        t.setSatellites(dto.getSatellites());
        t.setTimestamp(LocalDateTime.now());
        telemetryRepository.save(t);

        dto.setSerialNo(serialNo);
        dto.setTimestamp(t.getTimestamp().toString());
        broadcast(serialNo, dto);
        return dto;
    }

    public ModuleTelemetryDto getLatestTelemetry(String serialNo) {
        // P1: scope reads to the current binding so a re-bind cannot leak the
        // previous owner’s last GPS fix to the new owner. If the module is
        // unbound (boundAt == null) the API contract is “no data”.
        TraxModule module = moduleRepository.findBySerialNo(serialNo).orElse(null);
        if (module == null || module.getBoundAt() == null) return null;
        return telemetryRepository
                .findTopByModuleSerialNoAndTimestampGreaterThanEqualOrderByTimestampDesc(
                        serialNo, module.getBoundAt())
                .map(t -> toDto(serialNo, t)).orElse(null);
    }

    // ── ingest from vesc-iot ─────────────────────────────────────────

    /**
     * Persist a single decoded GpsFrame.  Idempotent on
     * {@code (module_id, ts_millis)} — duplicate calls (e.g. same frame
     * arriving via MQTT and via the App's BLE relay) become no-ops.
     *
     * @return true if a new row was inserted, false if it was a duplicate
     *         or the module/serial is unknown.
     */
    public boolean recordFromGpsFrame(GpsFrame frame) {
        if (frame == null || frame.getDeviceId() == null) return false;
        // Drop "no GNSS fix" sentinels (lat=90,lon=0) and null-island (0,0) so
        // they never reach module_telemetry OR ride_points — they would
        // teleport replay tracks to the North Pole and inflate distance.
        if (!LocationIngestService.coordsValid(frame.getLat(), frame.getLon())) {
            log.debug("recordFromGpsFrame: dropped invalid coords serial={} lat={} lon={}",
                    frame.getDeviceId(), frame.getLat(), frame.getLon());
            return false;
        }
        TraxModule module = moduleRepository.findBySerialNo(frame.getDeviceId()).orElse(null);
        if (module == null) {
            log.debug("recordFromGpsFrame: unknown module serial={}", frame.getDeviceId());
            return false;
        }
        long ts = frame.getTs() != null ? frame.getTs().toEpochMilli() : System.currentTimeMillis();
        if (telemetryRepository.existsByModuleIdAndTimestampMillis(module.getId(), ts)) {
            return false;
        }

        ModuleTelemetry t = new ModuleTelemetry();
        t.setModule(module);
        t.setLatitude(frame.getLat());
        t.setLongitude(frame.getLon());
        t.setAltitude(frame.getAlt());
        t.setSpeed(frame.getSpeed());
        t.setSatellites(frame.getSatellites());
        // Battery / signal not present in GpsFrame; preserve last known.
        ModuleTelemetry last = telemetryRepository
                .findTopByModuleSerialNoOrderByTimestampDesc(frame.getDeviceId()).orElse(null);
        if (last != null) {
            t.setBatteryPercent(last.getBatteryPercent());
            t.setSignalStrength(last.getSignalStrength());
        }
        t.setTimestamp(LocalDateTime.ofInstant(Instant.ofEpochMilli(ts), ZoneId.systemDefault()));
        t.setTimestampMillis(ts);

        try {
            telemetryRepository.save(t);
        } catch (DataIntegrityViolationException dup) {
            // Lost a race against another ingest path — treated as success.
            return false;
        }

        // Bridge into the unified location pipeline so this fix also reaches
        // ride_points (for lap detection / stats / race replay) when the bike
        // has a covering ride. Pure side-effect — telemetry row already saved.
        UnifiedLocationFrame uf = ModuleNmeaAdapter.fromGpsFrame(frame);
        if (uf != null) {
            Optional<RidePoint> inserted = Optional.empty();
            try {
                inserted = locationIngestService.ingestModule(frame.getDeviceId(), uf);
            } catch (Exception e) {
                log.warn("ingestModule failed serial={} ts={} err={}",
                        frame.getDeviceId(), ts, e.toString());
            }
            // GAP #2 fix: a module-sourced frame just landed in ride_points but
            // the App may not be polling /stats. Trigger lap detection now so
            // the ride can auto-finish (and broadcast lap WS events) regardless
            // of whether anyone is watching.
            if (inserted.isPresent() && rideService != null) {
                Long rideId = inserted.get().getRide() != null
                        ? inserted.get().getRide().getId() : null;
                if (rideId != null) {
                    try {
                        rideService.detectLapsForRideId(rideId);
                    } catch (Exception e) {
                        log.warn("detectLapsForRideId failed ride={} err={}",
                                rideId, e.toString());
                    }
                    // Backend-driven adaptive sampling: boost this module to
                    // 5 Hz near the finish line, revert to 1 Hz on leave.
                    try {
                        samplingCoordinator.onModuleFix(
                                frame.getDeviceId(), rideId,
                                frame.getLat(), frame.getLon(), frame.getSpeed());
                    } catch (Exception e) {
                        log.warn("sampling onModuleFix failed serial={} ride={} err={}",
                                frame.getDeviceId(), rideId, e.toString());
                    }
                }
            }
            // Age-gate WS broadcast so backfill (BLE / MQTT-reconnect) doesn't
            // teleport live UIs to a stale fix. Realtime stays unaffected.
            if (locationIngestService.isLive(uf)) {
                broadcast(frame.getDeviceId(), toDto(frame.getDeviceId(), t));
            }
        } else {
            // No usable timestamp on the GpsFrame — still broadcast so live
            // UI works (server clock used for `t.timestamp`).
            broadcast(frame.getDeviceId(), toDto(frame.getDeviceId(), t));
        }
        return true;
    }

    /**
     * Batch-ingest NMEA $PCYCGPS lines forwarded by the App through its
     * BLE relay (offline-module path).  Returns the number of rows
     * actually inserted (excludes duplicates and undecodable lines).
     */
    public int recordBatchNmea(String serialNo, List<String> nmeaLines) {
        if (nmeaLines == null || nmeaLines.isEmpty()) return 0;
        int kept = 0;
        List<String> bad = new ArrayList<>();
        for (String line : nmeaLines) {
            if (line == null || line.isBlank()) continue;
            try {
                GpsFrame frame = NmeaGpsCodec.decodeLine(serialNo, line.trim());
                if (recordFromGpsFrame(frame)) kept++;
            } catch (Exception e) {
                bad.add(line);
            }
        }
        if (!bad.isEmpty()) {
            log.warn("recordBatchNmea: {} undecodable line(s) for serial={}", bad.size(), serialNo);
        }
        return kept;
    }

    // ── helpers ──────────────────────────────────────────────────────

    private ModuleTelemetryDto toDto(String serialNo, ModuleTelemetry t) {
        ModuleTelemetryDto dto = new ModuleTelemetryDto();
        dto.setSerialNo(serialNo);
        dto.setLatitude(t.getLatitude());
        dto.setLongitude(t.getLongitude());
        dto.setAltitude(t.getAltitude());
        dto.setSpeed(t.getSpeed());
        dto.setBatteryPercent(t.getBatteryPercent());
        dto.setSignalStrength(t.getSignalStrength());
        dto.setSatellites(t.getSatellites());
        dto.setTimestamp(t.getTimestamp() != null ? t.getTimestamp().toString() : null);
        return dto;
    }

    private void broadcast(String serialNo, ModuleTelemetryDto dto) {
        if (wsHandler != null) wsHandler.broadcast(serialNo, dto);
    }
}
