package com.trax.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.trax.dto.RideLapEventDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-ride fan-out handler for lap-completion events. Clients connect to
 * {@code /ws/rides/{rideId}/laps}; the rideId is parsed and ownership
 * checked in {@link RideLapWsHandshakeInterceptor}.
 *
 * <p>The handler is sink-only: subscribers receive JSON-encoded
 * {@link RideLapEventDto} whenever {@code RideService.detectAndPersistLaps}
 * closes a new lap or auto-completes the ride. After a {@code completed}
 * event is broadcast, all sessions for that rideId are force-closed since
 * no further events are expected.
 */
@Component
public class RideLapWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(RideLapWebSocketHandler.class);

    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<Long, Set<WebSocketSession>> byRide = new ConcurrentHashMap<>();

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        Long rideId = rideIdOf(session);
        if (rideId == null) {
            try { session.close(CloseStatus.BAD_DATA); } catch (IOException ignored) {}
            return;
        }
        byRide.computeIfAbsent(rideId, k -> ConcurrentHashMap.newKeySet()).add(session);
        log.info("Lap WS connected ride={}, total={}", rideId, byRide.get(rideId).size());
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        Long rideId = rideIdOf(session);
        if (rideId == null) return;
        Set<WebSocketSession> set = byRide.get(rideId);
        if (set != null) {
            set.remove(session);
            if (set.isEmpty()) byRide.remove(rideId);
        }
    }

    /** Broadcast the event to every client subscribed to that rideId. */
    public void broadcast(Long rideId, RideLapEventDto dto) {
        if (rideId == null) return;
        Set<WebSocketSession> set = byRide.get(rideId);
        if (set == null || set.isEmpty()) return;
        String json;
        try {
            json = mapper.writeValueAsString(dto);
        } catch (Exception e) {
            log.warn("Lap WS serialize failed: {}", e.toString());
            return;
        }
        TextMessage msg = new TextMessage(json);
        for (WebSocketSession s : set) {
            try {
                if (s.isOpen()) s.sendMessage(msg);
            } catch (IOException e) {
                log.debug("Lap WS send failed ride={}: {}", rideId, e.toString());
            }
        }
        // After a completion event no further events will be sent; force-close
        // so clients drop the connection promptly instead of holding it open
        // until the read timeout.
        if ("completed".equals(dto.getType())) {
            closeRide(rideId);
        }
    }

    /** Force-close every live subscriber for this ride. */
    public void closeRide(Long rideId) {
        if (rideId == null) return;
        Set<WebSocketSession> set = byRide.remove(rideId);
        if (set == null) return;
        for (WebSocketSession s : set) {
            try { s.close(CloseStatus.NORMAL); } catch (IOException ignored) {}
        }
        log.info("Lap WS closed all sessions for ride={}", rideId);
    }

    private static Long rideIdOf(WebSocketSession session) {
        Object v = session.getAttributes().get("rideId");
        if (v instanceof Long l) return l;
        if (v instanceof Number n) return n.longValue();
        if (v != null) {
            try { return Long.parseLong(v.toString()); } catch (NumberFormatException ignored) {}
        }
        return null;
    }
}
