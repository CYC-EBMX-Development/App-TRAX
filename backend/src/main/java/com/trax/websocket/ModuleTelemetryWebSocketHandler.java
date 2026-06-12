package com.trax.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.trax.dto.ModuleTelemetryDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-serial fan-out handler.  Each connected client subscribes to a
 * single module's telemetry stream via URI {@code /ws/modules/{serialNo}/telemetry};
 * the serial is parsed in {@link ModuleTelemetryWsHandshakeInterceptor}
 * and stored in session attributes under key {@code "serialNo"}.
 *
 * The handler is sink-only: the App connects and waits; backend pushes
 * JSON-encoded {@link ModuleTelemetryDto} whenever a new MQTT/BLE-relay
 * frame is recorded.
 */
@Component
public class ModuleTelemetryWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(ModuleTelemetryWebSocketHandler.class);

    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, Set<WebSocketSession>> bySerial = new ConcurrentHashMap<>();

    /** Serialize concurrent sends per session: Tomcat's WebSocketSession is
     *  NOT re-entrant, so at 5 Hz a still-flushing TEXT frame + the next send
     *  throws IllegalStateException (TEXT_PARTIAL_WRITING) and kills the
     *  socket. The decorator queues sends behind a buffer instead. */
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
        log.info("WS connected serial={}, total={}", serial, bySerial.get(serial).size());
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

    /** Broadcast the latest telemetry to every client subscribed to that serial. */
    public void broadcast(String serialNo, ModuleTelemetryDto dto) {
        Set<WebSocketSession> set = bySerial.get(serialNo);
        if (set == null || set.isEmpty()) return;
        String json;
        try {
            json = mapper.writeValueAsString(dto);
        } catch (Exception e) {
            log.warn("WS serialize failed: {}", e.toString());
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
                log.debug("WS send failed serial={}: {}", serialNo, e.toString());
            }
        }
    }

    private static String serialOf(WebSocketSession session) {
        Object v = session.getAttributes().get("serialNo");
        return v == null ? null : v.toString();
    }

    /**
     * Force-close every live subscriber for this serial. Called by
     * {@code BicycleService} when the bike is forgotten or the module is
     * unbound / re-bound so the previous owner stops receiving frames
     * immediately (otherwise they’d remain subscribed until network
     * disconnect or app restart).
     */
    public void closeSerial(String serialNo) {
        if (serialNo == null) return;
        Set<WebSocketSession> set = bySerial.remove(serialNo);
        if (set == null) return;
        for (WebSocketSession s : set) {
            try { s.close(CloseStatus.POLICY_VIOLATION); } catch (IOException ignored) {}
        }
        log.info("WS closed all sessions for serial={} (binding changed)", serialNo);
    }
}
