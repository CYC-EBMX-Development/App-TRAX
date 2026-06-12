package com.trax.service;

import com.cyc.iot.common.codec.NmeaGpsCodec;
import com.cyc.iot.common.model.GpsFrame;
import com.hivemq.client.mqtt.MqttGlobalPublishFilter;
import com.hivemq.client.mqtt.datatypes.MqttQos;
import com.hivemq.client.mqtt.mqtt5.Mqtt5AsyncClient;
import com.hivemq.client.mqtt.mqtt5.message.publish.Mqtt5Publish;
import com.trax.config.MqttProperties;
import com.trax.config.MqttSessionResetEvent;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Subscribes to {@code $share/<group>/+/position} on the vesc-iot MQTT
 * broker, decodes NMEA $PCYCGPS frames, persists them through
 * {@link ModuleTelemetryService#recordFromGpsFrame(GpsFrame)} and lets
 * the service broadcast latest state via WebSocket.
 *
 * topic format: {@code <deviceId>/position} where {@code deviceId} is the
 * module's serial number — matches {@code TraxModule.serialNo}.
 */
@Service
@ConditionalOnBean(Mqtt5AsyncClient.class)
public class MqttSubscriberService {
    private static final Logger log = LoggerFactory.getLogger(MqttSubscriberService.class);

    private final Mqtt5AsyncClient client;
    private final MqttProperties props;
    private final ModuleTelemetryService telemetryService;

    public MqttSubscriberService(Mqtt5AsyncClient client,
                                 MqttProperties props,
                                 ModuleTelemetryService telemetryService) {
        this.client = client;
        this.props = props;
        this.telemetryService = telemetryService;
    }

    @PostConstruct
    void init() {
        // Register the publish callback ONCE globally. Re-subscribing on a
        // session reset must not register a fresh per-subscription callback
        // (that would double-deliver and double-persist every frame).
        client.publishes(MqttGlobalPublishFilter.ALL, this::route);
        subscribe();
    }

    /** Re-issue the shared subscription after the broker session was lost. */
    @EventListener
    public void onSessionReset(MqttSessionResetEvent event) {
        log.warn("MQTT session reset — re-subscribing position");
        subscribe();
    }

    private void subscribe() {
        String topic = String.format("$share/%s/+/position", props.getShareGroup());
        client.subscribeWith()
                .topicFilter(topic)
                .qos(MqttQos.AT_LEAST_ONCE)
                .send()
                .whenComplete((ack, err) -> {
                    if (err != null) {
                        log.error("MQTT subscribe {} failed", topic, err);
                    } else {
                        log.info("MQTT subscribed: {}", topic);
                    }
                });
    }

    /** Global publish dispatcher — handles only the {@code position} suffix. */
    private void route(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        int slash = topic.lastIndexOf('/');
        String suffix = slash < 0 ? topic : topic.substring(slash + 1);
        if (!"position".equals(suffix)) return; // imu handled by its own service
        onPosition(msg);
    }

    private void onPosition(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        String deviceId = extractDeviceId(topic);
        byte[] payload = msg.getPayloadAsBytes();
        try {
            List<GpsFrame> frames = NmeaGpsCodec.decode(deviceId, payload);
            int kept = 0;
            for (GpsFrame f : frames) {
                if (telemetryService.recordFromGpsFrame(f)) kept++;
            }
            if (kept > 0) log.debug("MQTT position dev={}, kept={}/{}", deviceId, kept, frames.size());
        } catch (Exception e) {
            log.warn("MQTT position decode failed dev={}, err={}", deviceId, e.toString());
        }
    }

    /** Extract device_id (first slash-delimited segment) from an MQTT topic. */
    static String extractDeviceId(String topic) {
        if (topic == null) return null;
        int slash = topic.indexOf('/');
        return slash < 0 ? topic : topic.substring(0, slash);
    }
}
