package com.trax.websocket;

import com.cyc.iot.common.model.ImuFrame;
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
 * Per-serial fan-out handler for live IMU frames at
 * {@code /ws/modules/{serialNo}/imu}. Sink-only: subscribers receive
 * JSON-encoded {@link ImuFrame}s as they arrive on MQTT topic
 * {@code <deviceId>/imu}.
 *
 * IMU is high-rate (firmware emits at 50–200 Hz) and ephemeral — nothing
 * is persisted. If no subscribers are connected for a serial, decoded
 * frames are dropped.
 */
@Component
public class ModuleImuWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(ModuleImuWebSocketHandler.class);

    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, Set<WebSocketSession>> bySerial = new ConcurrentHashMap<>();

    /** Serialize concurrent sends per session. IMU is 50–200 Hz, so a
     *  still-flushing frame + the next send would otherwise throw Tomcat's
     *  IllegalStateException (TEXT_PARTIAL_WRITING) and kill the socket. */
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
        log.info("IMU WS connected serial={}, total={}", serial, bySerial.get(serial).size());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String serial = serialOf(session);
        if (serial == null) return;
        Set<WebSocketSession> set = bySerial.get(serial);
        if (set != null) {
            // Stored sessions are decorators; match by underlying session id.
            set.removeIf(s -> s.getId().equals(session.getId()));
            if (set.isEmpty()) bySerial.remove(serial);
        }
    }

    /** Whether any subscriber is currently listening for a given serial. */
    public boolean hasSubscribers(String serialNo) {
        Set<WebSocketSession> set = bySerial.get(serialNo);
        return set != null && !set.isEmpty();
    }

    /** Broadcast a single IMU frame to every subscriber of that serial. */
    public void broadcast(String serialNo, ImuFrame frame) {
        Set<WebSocketSession> set = bySerial.get(serialNo);
        if (set == null || set.isEmpty()) return;
        // Hand-build the map to keep the wire format stable and human-readable
        // (Lombok @Data on ImuFrame would otherwise include the deviceId twice
        // and emit instants as nanos).
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("serialNo", serialNo);
        out.put("ts", frame.getTs() == null ? null : frame.getTs().toString());
        out.put("ax", frame.getAx());
        out.put("ay", frame.getAy());
        out.put("az", frame.getAz());
        out.put("gx", frame.getGx());
        out.put("gy", frame.getGy());
        out.put("gz", frame.getGz());
        out.put("roll", frame.getRoll());
        out.put("pitch", frame.getPitch());
        out.put("yaw", frame.getYaw());
        out.put("q0", frame.getQ0());
        out.put("q1", frame.getQ1());
        out.put("q2", frame.getQ2());
        out.put("q3", frame.getQ3());
        String json;
        try {
            json = mapper.writeValueAsString(out);
        } catch (Exception e) {
            log.warn("IMU WS serialize failed: {}", e.toString());
            return;
        }
        TextMessage msg = new TextMessage(json);
        for (WebSocketSession s : set) {
            try {
                if (s.isOpen()) s.sendMessage(msg);
            } catch (Exception e) {
                // Broaden beyond IOException: Tomcat send failures surface as
                // RuntimeException (IllegalStateException). One bad session must
                // never abort the broadcast loop for the others.
                log.debug("IMU WS send failed serial={}: {}", serialNo, e.toString());
            }
        }
    }

    /** Force-close every live IMU subscriber for this serial (on rebind / forget). */
    public void closeSerial(String serialNo) {
        if (serialNo == null) return;
        Set<WebSocketSession> set = bySerial.remove(serialNo);
        if (set == null) return;
        for (WebSocketSession s : set) {
            try { s.close(CloseStatus.POLICY_VIOLATION); } catch (IOException ignored) {}
        }
        log.info("IMU WS closed all sessions for serial={} (binding changed)", serialNo);
    }

    private static String serialOf(WebSocketSession session) {
        Object v = session.getAttributes().get("serialNo");
        return v == null ? null : v.toString();
    }
}
