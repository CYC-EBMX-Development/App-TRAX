package com.trax.websocket;

import com.trax.model.RideRecord;
import com.trax.repository.RideRecordRepository;
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
 * Captures the {@code rideId} path variable from
 * {@code /ws/rides/{rideId}/laps} into WebSocket session attributes and
 * enforces that the JWT-identified caller is the owner of that ride.
 * Rejects the handshake with 401/403 otherwise.
 */
@Component
public class RideLapWsHandshakeInterceptor implements HandshakeInterceptor {
    private static final Logger log = LoggerFactory.getLogger(RideLapWsHandshakeInterceptor.class);

    private final JwtUtil jwtUtil;
    private final UserRepository userRepository;
    private final RideRecordRepository rideRecordRepository;

    public RideLapWsHandshakeInterceptor(JwtUtil jwtUtil,
                                          UserRepository userRepository,
                                          RideRecordRepository rideRecordRepository) {
        this.jwtUtil = jwtUtil;
        this.userRepository = userRepository;
        this.rideRecordRepository = rideRecordRepository;
    }

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                   WebSocketHandler wsHandler, Map<String, Object> attributes) {
        if (!(request instanceof ServletServerHttpRequest s)) {
            response.setStatusCode(HttpStatus.BAD_REQUEST);
            return false;
        }
        HttpServletRequest http = s.getServletRequest();

        // 1) Extract rideId from path /ws/rides/{rideId}/laps
        Long rideId = null;
        String[] parts = http.getRequestURI().split("/");
        for (int i = 0; i < parts.length - 1; i++) {
            if ("rides".equals(parts[i])) {
                try {
                    rideId = Long.parseLong(parts[i + 1]);
                } catch (NumberFormatException ignored) {}
                break;
            }
        }
        if (rideId == null) {
            response.setStatusCode(HttpStatus.BAD_REQUEST);
            return false;
        }

        // 2) Extract token from Authorization: Bearer ... or ?token= query param.
        String token = null;
        String authHeader = http.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            token = authHeader.substring(7);
        } else {
            token = http.getParameter("token");
        }
        if (token == null || token.isBlank() || !jwtUtil.validateToken(token)) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            log.debug("Lap WS handshake rejected ride={}: missing/invalid token", rideId);
            return false;
        }

        // 3) Verify caller owns the ride.
        String email = jwtUtil.extractEmail(token);
        Long callerId = userRepository.findByEmail(email).map(u -> u.getId()).orElse(null);
        if (callerId == null) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }
        RideRecord ride = rideRecordRepository.findById(rideId).orElse(null);
        if (ride == null || ride.getUser() == null
                || !callerId.equals(ride.getUser().getId())) {
            response.setStatusCode(HttpStatus.FORBIDDEN);
            log.info("Lap WS handshake rejected ride={} caller={}: not owner", rideId, callerId);
            return false;
        }

        attributes.put("rideId", rideId);
        attributes.put("userId", callerId);
        return true;
    }

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
                               WebSocketHandler wsHandler, Exception exception) {
        // no-op
    }
}
