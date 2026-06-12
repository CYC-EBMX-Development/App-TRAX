package com.trax.signal;

import com.trax.model.Bicycle;
import com.trax.model.RidePoint;
import com.trax.model.RideRecord;
import com.trax.repository.BicycleRepository;
import com.trax.repository.RidePointRepository;
import com.trax.repository.RideRecordRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class LocationIngestServiceTest {

    @Mock BicycleRepository bicycleRepository;
    @Mock RideRecordRepository rideRecordRepository;
    @Mock RidePointRepository ridePointRepository;
    @InjectMocks LocationIngestService ingest;

    private Bicycle bike;
    private RideRecord ride;

    @BeforeEach
    void setUp() {
        bike = new Bicycle();
        bike.setId(42L);
        bike.setTraxSerialNumber("vesc_express");

        ride = new RideRecord();
        ride.setId(7L);
    }

    private UnifiedLocationFrame moduleFrame(long capturedAtMs) {
        return new UnifiedLocationFrame(
                capturedAtMs, 31.0, 121.0, 10.0, 5.0, 180.0, 1.0,
                SignalSource.MODULE, "vesc_express");
    }

    private UnifiedLocationFrame phoneFrame(long capturedAtMs) {
        return new UnifiedLocationFrame(
                capturedAtMs, 22.5, 113.9, 15.0, 8.0, null, null,
                SignalSource.PHONE, "phone-A");
    }

    // ── isLive ────────────────────────────────────────────────

    @Test
    void isLiveTrueForRecentFrame() {
        assertThat(ingest.isLive(moduleFrame(System.currentTimeMillis() - 1_000))).isTrue();
    }

    @Test
    void isLiveFalseForStaleFrame() {
        assertThat(ingest.isLive(moduleFrame(System.currentTimeMillis() - 60_000))).isFalse();
    }

    @Test
    void isLiveFalseForNull() {
        assertThat(ingest.isLive(null)).isFalse();
    }

    // ── sanity gates ──────────────────────────────────────────

    @Test
    void ingestModuleRejectsFutureFrame() {
        UnifiedLocationFrame future = moduleFrame(System.currentTimeMillis() + 5L * 60_000);

        Optional<RidePoint> result = ingest.ingestModule("vesc_express", future);

        assertThat(result).isEmpty();
        verify(bicycleRepository, never()).findByTraxSerialNumber(any());
    }

    @Test
    void ingestModuleRejectsTooOldFrame() {
        long ancient = System.currentTimeMillis() - 30L * 24 * 3600_000L;
        UnifiedLocationFrame stale = moduleFrame(ancient);

        Optional<RidePoint> result = ingest.ingestModule("vesc_express", stale);

        assertThat(result).isEmpty();
        verify(bicycleRepository, never()).findByTraxSerialNumber(any());
    }

    // ── ingestModule ──────────────────────────────────────────

    @Test
    void ingestModuleReturnsEmptyForBlankSerial() {
        assertThat(ingest.ingestModule(null, moduleFrame(System.currentTimeMillis()))).isEmpty();
        assertThat(ingest.ingestModule(" ", moduleFrame(System.currentTimeMillis()))).isEmpty();
        verify(bicycleRepository, never()).findByTraxSerialNumber(any());
    }

    @Test
    void ingestModuleReturnsEmptyWhenSerialUnknown() {
        when(bicycleRepository.findByTraxSerialNumber("vesc_express")).thenReturn(List.of());

        Optional<RidePoint> r = ingest.ingestModule("vesc_express",
                moduleFrame(System.currentTimeMillis()));

        assertThat(r).isEmpty();
        verify(rideRecordRepository, never()).findRideCoveringTime(anyLong(), any());
    }

    @Test
    void ingestModuleReturnsEmptyWhenNoCoveringRide() {
        when(bicycleRepository.findByTraxSerialNumber("vesc_express")).thenReturn(List.of(bike));
        when(rideRecordRepository.findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class)))
                .thenReturn(List.of());

        Optional<RidePoint> r = ingest.ingestModule("vesc_express",
                moduleFrame(System.currentTimeMillis()));

        assertThat(r).isEmpty();
        verify(ridePointRepository, never()).save(any());
    }

    @Test
    void ingestModuleSavesPointWithCorrectFields() {
        long ts = System.currentTimeMillis() - 1_000;
        when(bicycleRepository.findByTraxSerialNumber("vesc_express")).thenReturn(List.of(bike));
        when(rideRecordRepository.findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class)))
                .thenReturn(List.of(ride));
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(false);
        when(ridePointRepository.save(any(RidePoint.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        Optional<RidePoint> r = ingest.ingestModule("vesc_express", moduleFrame(ts));

        assertThat(r).isPresent();
        ArgumentCaptor<RidePoint> cap = ArgumentCaptor.forClass(RidePoint.class);
        verify(ridePointRepository).save(cap.capture());
        RidePoint saved = cap.getValue();
        assertThat(saved.getRide()).isSameAs(ride);
        assertThat(saved.getLatitude()).isEqualTo(31.0);
        assertThat(saved.getLongitude()).isEqualTo(121.0);
        assertThat(saved.getSpeed()).isEqualTo(5.0);
        assertThat(saved.getAltitude()).isEqualTo(10.0);
        assertThat(saved.getCapturedAtMs()).isEqualTo(ts);
        assertThat(saved.getSource()).isEqualTo("module");
        assertThat(saved.getTimestamp()).isNotNull();
    }

    @Test
    void ingestModuleDedupsByCapturedAtMs() {
        long ts = System.currentTimeMillis() - 1_000;
        when(bicycleRepository.findByTraxSerialNumber("vesc_express")).thenReturn(List.of(bike));
        when(rideRecordRepository.findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class)))
                .thenReturn(List.of(ride));
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(true);

        Optional<RidePoint> r = ingest.ingestModule("vesc_express", moduleFrame(ts));

        assertThat(r).isEmpty();
        verify(ridePointRepository, never()).save(any());
    }

    @Test
    void ingestModulePicksMostRecentlyBoundBikeWhenDuplicates() {
        Bicycle legacy = new Bicycle();
        legacy.setId(1L);
        legacy.setTraxSerialNumber("vesc_express");
        long ts = System.currentTimeMillis() - 1_000;

        when(bicycleRepository.findByTraxSerialNumber("vesc_express"))
                .thenReturn(List.of(legacy, bike)); // last = most recent
        when(rideRecordRepository.findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class)))
                .thenReturn(List.of(ride));
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(false);
        when(ridePointRepository.save(any(RidePoint.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        Optional<RidePoint> r = ingest.ingestModule("vesc_express", moduleFrame(ts));

        assertThat(r).isPresent();
        verify(rideRecordRepository).findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class));
    }

    @Test
    void ingestModuleTreatsDataIntegrityViolationAsDedup() {
        long ts = System.currentTimeMillis() - 1_000;
        when(bicycleRepository.findByTraxSerialNumber("vesc_express")).thenReturn(List.of(bike));
        when(rideRecordRepository.findRideCoveringTime(eqBikeId(42L), any(LocalDateTime.class)))
                .thenReturn(List.of(ride));
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(false);
        when(ridePointRepository.save(any(RidePoint.class)))
                .thenThrow(new DataIntegrityViolationException("dup"));

        Optional<RidePoint> r = ingest.ingestModule("vesc_express", moduleFrame(ts));

        assertThat(r).isEmpty();
    }

    // ── ingestPhone ───────────────────────────────────────────

    @Test
    void ingestPhoneReturnsEmptyForNullRide() {
        assertThat(ingest.ingestPhone(null, phoneFrame(System.currentTimeMillis()))).isEmpty();
    }

    @Test
    void ingestPhoneSavesPointWithSourcePhone() {
        long ts = System.currentTimeMillis() - 500;
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(false);
        when(ridePointRepository.save(any(RidePoint.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        Optional<RidePoint> r = ingest.ingestPhone(ride, phoneFrame(ts));

        assertThat(r).isPresent();
        ArgumentCaptor<RidePoint> cap = ArgumentCaptor.forClass(RidePoint.class);
        verify(ridePointRepository).save(cap.capture());
        RidePoint saved = cap.getValue();
        assertThat(saved.getRide()).isSameAs(ride);
        assertThat(saved.getCapturedAtMs()).isEqualTo(ts);
        assertThat(saved.getSource()).isEqualTo("phone");
        // phone frame has null heading/hdop — must not blow up
        assertThat(saved.getLatitude()).isEqualTo(22.5);
    }

    @Test
    void ingestPhoneDedupsByCapturedAtMs() {
        long ts = System.currentTimeMillis() - 500;
        when(ridePointRepository.existsByRideIdAndCapturedAtMs(7L, ts)).thenReturn(true);

        Optional<RidePoint> r = ingest.ingestPhone(ride, phoneFrame(ts));

        assertThat(r).isEmpty();
        verify(ridePointRepository, never()).save(any());
    }

    /** Mockito argThat shortcut for clarity. */
    private static long eqBikeId(long id) {
        return org.mockito.ArgumentMatchers.longThat(v -> v == id);
    }
}
