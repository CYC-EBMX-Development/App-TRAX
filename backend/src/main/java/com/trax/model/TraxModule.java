package com.trax.model;

import jakarta.persistence.*;

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
    public BikeModel getModel() { return model; }
    public void setModel(BikeModel model) { this.model = model; }
}
