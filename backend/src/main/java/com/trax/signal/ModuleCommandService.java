package com.trax.signal;

import com.hivemq.client.mqtt.datatypes.MqttQos;
import com.hivemq.client.mqtt.mqtt5.Mqtt5AsyncClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;


/**
 * Sends downlink commands to a TRAX module by publishing to its
 * {@code <serial>/sub} topic on the vesc-iot MQTT broker.
 *
 * <p>The broker-side ACL grants the trax-backend MQTT account
 * ({@code iot_analytics}) {@code publish allow +/sub}, so the existing
 * {@link Mqtt5AsyncClient} bean can publish to any device's downlink topic
 * with no extra ACL.
 *
 * <p>Downlink command frames are the device's short serial protocol
 * ({@code 02 <type> 12 <data..> 03}) — distinct from the uplink telemetry
 * frame (magic {@code 0xA5C4BEEF} + CRC16). The bytes below are taken
 * verbatim from the protocol spec and sent opaquely (no CRC compute).
 */
@Service
public class ModuleCommandService {
    private static final Logger log = LoggerFactory.getLogger(ModuleCommandService.class);

    /** Config-frequency command: 5 Hz — {@code 02 02 12 05 35 B4 03}. */
    private static final byte[] CMD_FREQ_5HZ =
            {0x02, 0x02, 0x12, 0x05, 0x35, (byte) 0xB4, 0x03};
    /** Config-frequency command: 1 Hz — {@code 02 02 12 01 75 30 03}. */
    private static final byte[] CMD_FREQ_1HZ =
            {0x02, 0x02, 0x12, 0x01, 0x75, 0x30, 0x03};

    /** Optional — absent when {@code iot.mqtt.enabled=false} (e.g. tests). */
    @Autowired(required = false)
    private Mqtt5AsyncClient mqttClient;

    /**
     * Set the module's GPS sampling rate. No online pre-check: this is only
     * ever called for a device that is provably online (we just received a
     * GPS fix from it to decide it entered/left the finish zone), and the
     * watchdog revert targets the same just-seen device.
     *
     * @param serial module serial == MQTT clientId == downlink topic prefix
     * @param hz     5 (finish-line densification) or 1 (default cadence)
     */
    public void setSamplingHz(String serial, int hz) {
        if (serial == null || serial.isBlank()) return;
        if (hz != 1 && hz != 5) {
            log.warn("setSamplingHz: unsupported hz={} for {}", hz, serial);
            return;
        }
        if (mqttClient == null) {
            log.debug("setSamplingHz: MQTT disabled, skip {} -> {}Hz", serial, hz);
            return;
        }

        byte[] payload = hz == 5 ? CMD_FREQ_5HZ : CMD_FREQ_1HZ;
        String topic = serial + "/sub";
        mqttClient.publishWith()
                .topic(topic)
                .qos(MqttQos.AT_LEAST_ONCE)
                .payload(payload)
                .send()
                .whenComplete((ack, err) -> {
                    if (err != null) {
                        log.warn("module cmd publish {} {}Hz failed: {}", topic, hz, err.toString());
                    } else {
                        log.info("module cmd published: {} -> {}Hz", serial, hz);
                    }
                });
    }
}
