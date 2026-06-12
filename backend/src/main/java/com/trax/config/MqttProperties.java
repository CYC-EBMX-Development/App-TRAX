package com.trax.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Maps to {@code iot.mqtt.*} in application.yml. Mirrors
 * {@code com.cyc.iot.ingest.config.MqttProperties} so trax-backend can
 * subscribe to the same vesc-iot broker.
 */
@ConfigurationProperties(prefix = "iot.mqtt")
public class MqttProperties {
    private boolean enabled = true;
    private String host = "127.0.0.1";
    private int port = 1883;
    private String clientId = "trax-backend";
    private String username;
    private String password;
    private boolean cleanStart = false;
    private int keepAlive = 60;
    /** Shared-subscription group; multiple trax-backend instances in the
     *  same group will load-balance position messages. */
    private String shareGroup = "trax-backend";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }
    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }
    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public boolean isCleanStart() { return cleanStart; }
    public void setCleanStart(boolean cleanStart) { this.cleanStart = cleanStart; }
    public int getKeepAlive() { return keepAlive; }
    public void setKeepAlive(int keepAlive) { this.keepAlive = keepAlive; }
    public String getShareGroup() { return shareGroup; }
    public void setShareGroup(String shareGroup) { this.shareGroup = shareGroup; }
}
