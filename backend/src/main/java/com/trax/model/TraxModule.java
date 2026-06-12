package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "trax_module")
public class TraxModule {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String serialNo;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false)
    private boolean bound = false;

    /**
     * Wall-clock moment of the most recent successful bind. NULL when never
     * bound or currently unbound. Used by {@code ModuleTelemetryService} to
     * hide telemetry that arrived for a previous owner — read paths filter
     * with {@code timestamp >= boundAt} so a re-bind cannot leak the old
     * owner's position to the new one.
     */
    @Column(name = "bound_at")
    private LocalDateTime boundAt;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "model_id")
    private BikeModel model;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getSerialNo() { return serialNo; }
    public void setSerialNo(String serialNo) { this.serialNo = serialNo; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public boolean isBound() { return bound; }
    public void setBound(boolean bound) { this.bound = bound; }
    public LocalDateTime getBoundAt() { return boundAt; }
    public void setBoundAt(LocalDateTime boundAt) { this.boundAt = boundAt; }
    public BikeModel getModel() { return model; }
    public void setModel(BikeModel model) { this.model = model; }
}
