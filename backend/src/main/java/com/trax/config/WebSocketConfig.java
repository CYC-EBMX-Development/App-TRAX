package com.trax.config;

import com.trax.websocket.ModuleCtrlWebSocketHandler;
import com.trax.websocket.ModuleImuWebSocketHandler;
import com.trax.websocket.ModuleTelemetryWebSocketHandler;
import com.trax.websocket.ModuleTelemetryWsHandshakeInterceptor;
import com.trax.websocket.RideLapWebSocketHandler;
import com.trax.websocket.RideLapWsHandshakeInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {
    private final ModuleTelemetryWebSocketHandler telemetryHandler;
    private final ModuleImuWebSocketHandler imuHandler;
    private final ModuleCtrlWebSocketHandler ctrlHandler;
    private final ModuleTelemetryWsHandshakeInterceptor handshakeInterceptor;
    private final RideLapWebSocketHandler lapHandler;
    private final RideLapWsHandshakeInterceptor lapHandshakeInterceptor;

    public WebSocketConfig(ModuleTelemetryWebSocketHandler telemetryHandler,
                           ModuleImuWebSocketHandler imuHandler,
                           ModuleCtrlWebSocketHandler ctrlHandler,
                           ModuleTelemetryWsHandshakeInterceptor handshakeInterceptor,
                           RideLapWebSocketHandler lapHandler,
                           RideLapWsHandshakeInterceptor lapHandshakeInterceptor) {
        this.telemetryHandler = telemetryHandler;
        this.imuHandler = imuHandler;
        this.ctrlHandler = ctrlHandler;
        this.handshakeInterceptor = handshakeInterceptor;
        this.lapHandler = lapHandler;
        this.lapHandshakeInterceptor = lapHandshakeInterceptor;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(telemetryHandler, "/ws/modules/*/telemetry")
                .addInterceptors(handshakeInterceptor)
                .setAllowedOriginPatterns("*");
        // Same handshake interceptor: it parses serial after the
        // `modules` segment and authorizes ownership regardless of the
        // trailing path. IMU stream is push-only, no persistence.
        registry.addHandler(imuHandler, "/ws/modules/*/imu")
                .addInterceptors(handshakeInterceptor)
                .setAllowedOriginPatterns("*");
        // Live controller telemetry (temp/current/voltage/duty/...). Push-only,
        // not the persistence path (CtrlIngestService writes ride_ctrl_points).
        registry.addHandler(ctrlHandler, "/ws/modules/*/ctrl")
                .addInterceptors(handshakeInterceptor)
                .setAllowedOriginPatterns("*");
        // Per-ride lap-completion push. Handshake interceptor authorizes
        // that the JWT-identified caller owns the ride. Push-only.
        registry.addHandler(lapHandler, "/ws/rides/*/laps")
                .addInterceptors(lapHandshakeInterceptor)
                .setAllowedOriginPatterns("*");
    }
}
