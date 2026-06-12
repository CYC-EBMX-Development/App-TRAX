package com.trax.websocket;

import com.cyc.iot.common.model.CtrlFrame;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-serial fan-out handler for live controller telemetry at
 * {@code /ws/modules/{serialNo}/ctrl}. Sink-only: subscribers receive
 * JSON-encoded {@link CtrlFrame}s as they arrive on MQTT topic
 * {@code <deviceId>/ctrl}.
 *
 * Live diagnostics only — this stream is NOT the persistence path
 * ({@code CtrlIngestService} writes ride_ctrl_points independently). If no
 * subscriber is connected for a serial, broadcasts are skipped.
 */
@Component
public class ModuleCtrlWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(ModuleCtrlWebSocketHandler.class);

    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, Set<WebSocketSession>> bySerial = new ConcurrentHashMap<>();

    /** Serialize concurrent sends per session (ctrl batches arrive in bursts). */
    private static final int SEND_TIME_LIMIT_MS = 5_000;
    private static final int SEND_BUFFER_LIMIT_BYTES = 256 * 1024;

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        String serial = serialOf(session);
        if (serial == null) {
            try { session.close(CloseStatus.BAD_DATA); } catch (IOException ignored) {}
            return;
        }
        WebSocketSession concurrent = new ConcurrentWebSocketSessionDecorator(
                session, SEND_TIME_LIMIT_MS, SEND_BUFFER_LIMIT_BYTES);
        bySerial.computeIfAbsent(serial, k -> ConcurrentHashMap.newKeySet()).add(concurrent);
        log.info("CTRL WS connected serial={}, total={}", serial, bySerial.get(serial).size());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String serial = serialOf(session);
        if (serial == null) return;
        Set<WebSocketSession> set = bySerial.get(serial);
        if (set != null) {
            set.removeIf(s -> s.getId().equals(session.getId()));
            if (set.isEmpty()) bySerial.remove(serial);
        }
    }

    /** Whether any subscriber is currently listening for a given serial. */
    public boolean hasSubscribers(String serialNo) {
        Set<WebSocketSession> set = bySerial.get(serialNo);
        return set != null && !set.isEmpty();
    }

    /** Broadcast a single ctrl frame to every subscriber of that serial. */
    public void broadcast(String serialNo, CtrlFrame frame) {
        Set<WebSocketSession> set = bySerial.get(serialNo);
        if (set == null || set.isEmpty()) return;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("serialNo", serialNo);
        out.put("ts", frame.getTs() == null ? null : frame.getTs().toString());
        out.put("temp_fet", frame.getTempFet());
        out.put("temp_motor", frame.getTempMotor());
        out.put("current_motor", frame.getCurrentMotor());
        out.put("current_input", frame.getCurrentInput());
        out.put("id", frame.getId());
        out.put("iq", frame.getIq());
        out.put("duty", frame.getDuty());
        out.put("v_in", frame.getVin());
        out.put("throttle", frame.getThrottle());
        out.put("regen", frame.getRegen());
        out.put("vd", frame.getVd());
        out.put("vq", frame.getVq());
        String json;
        try {
            json = mapper.writeValueAsString(out);
        } catch (Exception e) {
            log.warn("CTRL WS serialize failed: {}", e.toString());
            return;
        }
        TextMessage msg = new TextMessage(json);
        for (WebSocketSession s : set) {
            try {
                if (s.isOpen()) s.sendMessage(msg);
            } catch (Exception e) {
                // Tomcat send failures surface as RuntimeException; one bad
                // session must never abort the broadcast loop for the others.
                log.debug("CTRL WS send failed serial={}: {}", serialNo, e.toString());
            }
        }
    }

    /** Force-close every live ctrl subscriber for this serial (on rebind / forget). */
    public void closeSerial(String serialNo) {
        if (serialNo == null) return;
        Set<WebSocketSession> set = bySerial.remove(serialNo);
        if (set == null) return;
        for (WebSocketSession s : set) {
            try { s.close(CloseStatus.POLICY_VIOLATION); } catch (IOException ignored) {}
        }
        log.info("CTRL WS closed all sessions for serial={} (binding changed)", serialNo);
    }

    private static String serialOf(WebSocketSession session) {
        Object v = session.getAttributes().get("serialNo");
        return v == null ? null : v.toString();
    }
}
