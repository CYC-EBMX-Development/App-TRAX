package com.trax.service;

import com.cyc.iot.common.codec.NmeaImuCodec;
import com.cyc.iot.common.model.ImuFrame;
import com.hivemq.client.mqtt.MqttGlobalPublishFilter;
import com.hivemq.client.mqtt.datatypes.MqttQos;
import com.hivemq.client.mqtt.mqtt5.Mqtt5AsyncClient;
import com.hivemq.client.mqtt.mqtt5.message.publish.Mqtt5Publish;
import com.trax.config.MqttProperties;
import com.trax.config.MqttSessionResetEvent;
import com.trax.websocket.ModuleImuWebSocketHandler;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Subscribes to {@code $share/<group>/+/imu}, decodes NMEA $PCYCIMU
 * frames via {@link NmeaImuCodec}, and fans them out to live App
 * subscribers via {@link ModuleImuWebSocketHandler}.
 *
 * Frames are NOT persisted (IMU rate is 50–200 Hz). When no client is
 * subscribed for a given serial, decoded frames are silently dropped.
 */
@Service
@ConditionalOnBean(Mqtt5AsyncClient.class)
public class MqttImuSubscriberService {
    private static final Logger log = LoggerFactory.getLogger(MqttImuSubscriberService.class);

    private final Mqtt5AsyncClient client;
    private final MqttProperties props;
    private final ModuleImuWebSocketHandler imuWs;

    public MqttImuSubscriberService(Mqtt5AsyncClient client,
                                    MqttProperties props,
                                    ModuleImuWebSocketHandler imuWs) {
        this.client = client;
        this.props = props;
        this.imuWs = imuWs;
    }

    @PostConstruct
    void init() {
        // Register the publish callback ONCE globally; re-subscribing on a
        // session reset then never adds a duplicate callback.
        client.publishes(MqttGlobalPublishFilter.ALL, this::route);
        subscribe();
    }

    /** Re-issue the shared subscription after the broker session was lost. */
    @EventListener
    public void onSessionReset(MqttSessionResetEvent event) {
        log.warn("MQTT session reset — re-subscribing imu");
        subscribe();
    }

    private void subscribe() {
        String topic = String.format("$share/%s/+/imu", props.getShareGroup());
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

    /** Global publish dispatcher — handles only the {@code imu} suffix. */
    private void route(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        int slash = topic.lastIndexOf('/');
        String suffix = slash < 0 ? topic : topic.substring(slash + 1);
        if (!"imu".equals(suffix)) return; // position handled by its own service
        onImu(msg);
    }

    private void onImu(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        String deviceId = MqttSubscriberService.extractDeviceId(topic);
        // Skip decode entirely if no one is listening — saves CPU at high rate.
        if (!imuWs.hasSubscribers(deviceId)) return;
        byte[] payload = msg.getPayloadAsBytes();
        try {
            List<ImuFrame> frames = NmeaImuCodec.decode(deviceId, payload);
            for (ImuFrame f : frames) {
                imuWs.broadcast(deviceId, f);
            }
        } catch (Exception e) {
            log.debug("MQTT imu decode failed dev={}, err={}", deviceId, e.toString());
        }
    }
}
