package com.trax.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "ride_lap_checkpoints",
        uniqueConstraints = @UniqueConstraint(
                name = "uk_lap_seq",
                columnNames = {"lap_id", "sequence_index"}))
public class RideLapCheckpoint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "lap_id", nullable = false)
    private Long lapId;

    @Column(name = "sequence_index", nullable = false)
    private Integer sequenceIndex;

    @Column(name = "pass_time", nullable = false)
    private LocalDateTime passTime;

    private Double latitude;
    private Double longitude;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getLapId() { return lapId; }
    public void setLapId(Long lapId) { this.lapId = lapId; }
    public Integer getSequenceIndex() { return sequenceIndex; }
    public void setSequenceIndex(Integer sequenceIndex) { this.sequenceIndex = sequenceIndex; }
    public LocalDateTime getPassTime() { return passTime; }
    public void setPassTime(LocalDateTime passTime) { this.passTime = passTime; }
    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }
    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }
}
