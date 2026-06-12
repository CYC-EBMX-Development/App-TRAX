package com.trax.websocket;

import com.trax.repository.BicycleRepository;
import com.trax.repository.UserRepository;
import com.trax.security.JwtUtil;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;

import java.util.Map;

/**
 * Captures the {@code serialNo} path variable from
 * {@code /ws/modules/{serialNo}/telemetry} into the WebSocket session
 * attributes for use by {@link ModuleTelemetryWebSocketHandler}, and
 * enforces that the caller (identified by JWT in the {@code Authorization}
 * header or {@code ?token=} query param) is the owner of the bicycle
 * currently bound to that serial. Rejects the handshake with 401/403
 * otherwise so unauthenticated or non-owner clients can never subscribe.
 */
@Component
public class ModuleTelemetryWsHandshakeInterceptor implements HandshakeInterceptor {
    private static final Logger log = LoggerFactory.getLogger(ModuleTelemetryWsHandshakeInterceptor.class);

    private final JwtUtil jwtUtil;
    private final UserRepository userRepository;
    private final BicycleRepository bicycleRepository;

    public ModuleTelemetryWsHandshakeInterceptor(JwtUtil jwtUtil,
                                                 UserRepository userRepository,
                                                 BicycleRepository bicycleRepository) {
        this.jwtUtil = jwtUtil;
        this.userRepository = userRepository;
        this.bicycleRepository = bicycleRepository;
    }

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                   WebSocketHandler wsHandler, Map<String, Object> attributes) {
        if (!(request instanceof ServletServerHttpRequest s)) {
            response.setStatusCode(HttpStatus.BAD_REQUEST);
            return false;
        }
        HttpServletRequest http = s.getServletRequest();

        // 1) Extract serial from path /ws/modules/{serialNo}/telemetry
        String serial = null;
        String[] parts = http.getRequestURI().split("/");
        for (int i = 0; i < parts.length - 1; i++) {
            if ("modules".equals(parts[i])) { serial = parts[i + 1]; break; }
        }
        if (serial == null || serial.isBlank()) {
            response.setStatusCode(HttpStatus.BAD_REQUEST);
            return false;
        }

        // 2) Extract token from Authorization: Bearer ... or ?token= query param
        // (browsers cannot set custom headers on WS handshake, so query-param
        // is the supported fallback for web clients).
        String token = null;
        String authHeader = http.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            token = authHeader.substring(7);
        } else {
            token = http.getParameter("token");
        }
        if (token == null || token.isBlank() || !jwtUtil.validateToken(token)) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            log.debug("WS handshake rejected serial={}: missing/invalid token", serial);
            return false;
        }

        // 3) Look up caller and verify ownership of the bicycle bound to serial.
        String email = jwtUtil.extractEmail(token);
        Long callerId = userRepository.findByEmail(email).map(u -> u.getId()).orElse(null);
        if (callerId == null) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }
        // Tolerate legacy duplicates: pick the row owned by the caller, if any.
        boolean owned = bicycleRepository.findByTraxSerialNumber(serial).stream()
                .anyMatch(b -> b.getOwner() != null && callerId.equals(b.getOwner().getId()));
        if (!owned) {
            response.setStatusCode(HttpStatus.FORBIDDEN);
            log.info("WS handshake rejected serial={} caller={}: not owner", serial, callerId);
            return false;
        }

        attributes.put("serialNo", serial);
        attributes.put("userId", callerId);
        return true;
    }

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
                               WebSocketHandler wsHandler, Exception exception) {
    }
}
