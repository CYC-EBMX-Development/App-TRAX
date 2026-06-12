package com.trax.config;

import com.hivemq.client.mqtt.MqttClient;
import com.hivemq.client.mqtt.mqtt5.Mqtt5AsyncClient;
import com.hivemq.client.mqtt.mqtt5.lifecycle.Mqtt5ClientConnectedContext;
import com.hivemq.client.mqtt.mqtt5.lifecycle.Mqtt5ClientDisconnectedContext;
import com.hivemq.client.mqtt.mqtt5.message.connect.Mqtt5Connect;
import com.hivemq.client.mqtt.mqtt5.message.connect.Mqtt5ConnectBuilder;
import com.hivemq.client.mqtt.mqtt5.message.connect.connack.Mqtt5ConnAck;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Builds and connects the HiveMQ Mqtt5 client used by
 * {@link com.trax.service.MqttSubscriberService} to receive module
 * telemetry from the vesc-iot broker.  Only active when
 * {@code iot.mqtt.enabled=true} (default).
 */
@Configuration
@EnableConfigurationProperties(MqttProperties.class)
@ConditionalOnProperty(prefix = "iot.mqtt", name = "enabled", havingValue = "true", matchIfMissing = true)
public class MqttClientConfig {
    private static final Logger log = LoggerFactory.getLogger(MqttClientConfig.class);

    @Bean(destroyMethod = "disconnect")
    public Mqtt5AsyncClient mqttClient(MqttProperties props, ApplicationEventPublisher events) {
        // Pre-build the CONNECT (with credentials) once and reuse it for BOTH
        // the initial connect and EVERY reconnect. HiveMQ's automatic reconnect
        // does NOT re-carry the simpleAuth from a one-shot connectWith().send(),
        // so after an EMQX restart our reconnect was sending Username=undefined
        // and getting rejected (bad_username_or_password) — telemetry stopped.
        final Mqtt5Connect connect = buildConnect(props);

        Mqtt5AsyncClient client = MqttClient.builder()
                .useMqttVersion5()
                .identifier(props.getClientId())
                .serverHost(props.getHost())
                .serverPort(props.getPort())
                .addConnectedListener(ctx -> {
                    if (ctx instanceof Mqtt5ClientConnectedContext c5
                            && !c5.getConnAck().isSessionPresent()) {
                        // Broker has no session for us (first connect or EMQX
                        // was rebuilt) → our shared subscriptions are gone; ask
                        // the subscriber services to re-subscribe.
                        log.warn("MQTT connected, sessionPresent=false — triggering re-subscribe");
                        events.publishEvent(MqttSessionResetEvent.INSTANCE);
                    } else {
                        log.info("MQTT connected, session resumed");
                    }
                })
                .addDisconnectedListener(ctx -> {
                    Throwable cause = ctx.getCause();
                    log.warn("MQTT disconnected, will reconnect with credentials: {}",
                            cause == null ? "-" : cause.toString());
                    if (ctx instanceof Mqtt5ClientDisconnectedContext c5) {
                        // Re-apply the SAME CONNECT (with credentials) on every
                        // reconnect attempt — this is the fix for the lost-auth bug.
                        c5.getReconnector()
                                .reconnect(true)
                                .delay(3, TimeUnit.SECONDS)
                                .connect(connect);
                    }
                })
                .buildAsync();

        try {
            // Bounded wait so a slow/unreachable broker never blocks Spring startup.
            // The disconnected listener keeps retrying in the background regardless.
            Mqtt5ConnAck ack = client.connect(connect)
                    .toCompletableFuture()
                    .get(10, TimeUnit.SECONDS);
            log.info("MQTT connected: clientId={}, host={}:{}, reason={}",
                    props.getClientId(), props.getHost(), props.getPort(), ack.getReasonCode());
        } catch (Exception e) {
            // Don't crash boot: the reconnect loop will keep trying. Log loudly.
            log.error("MQTT initial connect failed (reconnect will retry): {}", e.toString());
        }
        return client;
    }

    /** Builds the CONNECT message (with credentials, if configured) reused on every connect. */
    private static Mqtt5Connect buildConnect(MqttProperties props) {
        Mqtt5ConnectBuilder b = Mqtt5Connect.builder()
                .cleanStart(props.isCleanStart())
                .keepAlive(props.getKeepAlive())
                .sessionExpiryInterval(props.isCleanStart() ? 0 : 86400);
        if (props.getUsername() != null && !props.getUsername().isBlank()) {
            b = b.simpleAuth()
                    .username(props.getUsername())
                    .password(props.getPassword().getBytes(StandardCharsets.UTF_8))
                    .applySimpleAuth();
        }
        return b.build();
    }
}
