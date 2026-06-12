package com.trax.service;

import com.cyc.iot.common.codec.CtrlBinaryCodec;
import com.cyc.iot.common.model.CtrlFrame;
import com.hivemq.client.mqtt.MqttGlobalPublishFilter;
import com.hivemq.client.mqtt.datatypes.MqttQos;
import com.hivemq.client.mqtt.mqtt5.Mqtt5AsyncClient;
import com.hivemq.client.mqtt.mqtt5.message.publish.Mqtt5Publish;
import com.trax.config.MqttProperties;
import com.trax.config.MqttSessionResetEvent;
import com.trax.signal.CtrlIngestService;
import com.trax.websocket.ModuleCtrlWebSocketHandler;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Subscribes to {@code $share/<group>/+/ctrl}, decodes the CYC binary
 * controller protocol via {@link CtrlBinaryCodec}, then:
 * <ul>
 *   <li>persists each frame to {@code ride_ctrl_points} via
 *       {@link CtrlIngestService} (throttled to GPS cadence, only while a
 *       ride is active) — the analysis-page data source, decoupled from
 *       vesc-iot;</li>
 *   <li>fans the frame out live to App subscribers on the module-detail
 *       page via {@link ModuleCtrlWebSocketHandler} (no persistence on this
 *       path).</li>
 * </ul>
 *
 * Ctrl is ~5 Hz (vs IMU 50–200 Hz), so decoding every payload unconditionally
 * is cheap — unlike the IMU service we do NOT gate decode on live subscribers,
 * because persistence must happen even when nobody is watching.
 */
@Service
@ConditionalOnBean(Mqtt5AsyncClient.class)
public class MqttCtrlSubscriberService {
    private static final Logger log = LoggerFactory.getLogger(MqttCtrlSubscriberService.class);

    private final Mqtt5AsyncClient client;
    private final MqttProperties props;
    private final CtrlIngestService ctrlIngest;
    private final ModuleCtrlWebSocketHandler ctrlWs;

    public MqttCtrlSubscriberService(Mqtt5AsyncClient client,
                                     MqttProperties props,
                                     CtrlIngestService ctrlIngest,
                                     ModuleCtrlWebSocketHandler ctrlWs) {
        this.client = client;
        this.props = props;
        this.ctrlIngest = ctrlIngest;
        this.ctrlWs = ctrlWs;
    }

    @PostConstruct
    void init() {
        client.publishes(MqttGlobalPublishFilter.ALL, this::route);
        subscribe();
    }

    @EventListener
    public void onSessionReset(MqttSessionResetEvent event) {
        log.warn("MQTT session reset — re-subscribing ctrl");
        subscribe();
    }

    private void subscribe() {
        String topic = String.format("$share/%s/+/ctrl", props.getShareGroup());
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

    /** Global publish dispatcher — handles only the {@code ctrl} suffix. */
    private void route(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        int slash = topic.lastIndexOf('/');
        String suffix = slash < 0 ? topic : topic.substring(slash + 1);
        if (!"ctrl".equals(suffix)) return; // position/imu handled by their own services
        onCtrl(msg);
    }

    private void onCtrl(Mqtt5Publish msg) {
        String topic = msg.getTopic().toString();
        String deviceId = MqttSubscriberService.extractDeviceId(topic);
        byte[] payload = msg.getPayloadAsBytes();
        try {
            List<CtrlFrame> frames = CtrlBinaryCodec.decodeAll(deviceId, payload);
            boolean live = ctrlWs.hasSubscribers(deviceId);
            for (CtrlFrame f : frames) {
                ctrlIngest.ingestModule(deviceId, f); // persist (throttled, ride-gated)
                if (live) ctrlWs.broadcast(deviceId, f);
            }
        } catch (Exception e) {
            log.debug("MQTT ctrl handle failed dev={}, err={}", deviceId, e.toString());
        }
    }
}
