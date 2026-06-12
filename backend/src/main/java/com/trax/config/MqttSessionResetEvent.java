package com.trax.config;

/**
 * Published when the MQTT client (re)connects and finds the broker has no
 * session for us ({@code sessionPresent=false} — e.g. EMQX was restarted or
 * rebuilt). Subscribers listen for this and re-issue their shared
 * subscriptions so module telemetry does not silently stop flowing.
 */
public final class MqttSessionResetEvent {
    public static final MqttSessionResetEvent INSTANCE = new MqttSessionResetEvent();

    private MqttSessionResetEvent() {
    }
}
