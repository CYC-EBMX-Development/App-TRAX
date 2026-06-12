package com.trax.service;

import com.trax.dto.BicycleDto;
import com.trax.model.*;
import com.trax.repository.*;
import com.trax.websocket.ModuleImuWebSocketHandler;
import com.trax.websocket.ModuleTelemetryWebSocketHandler;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@Transactional
public class BicycleService {
    private final BicycleRepository bicycleRepository;
    private final UserRepository userRepository;
    private final BikeModelRepository bikeModelRepository;
    private final TraxModuleRepository traxModuleRepository;
    private final RideRecordRepository rideRecordRepository;
    private final RidePointRepository ridePointRepository;
    private final HistoryBicycleRepository historyBicycleRepository;
    private final HistoryRideRecordRepository historyRideRecordRepository;
    private final HistoryRidePointRepository historyRidePointRepository;
    private final ModuleTelemetryWebSocketHandler telemetryWs;
    private final ModuleImuWebSocketHandler imuWs;

    public BicycleService(BicycleRepository bicycleRepository,
                         UserRepository userRepository,
                         BikeModelRepository bikeModelRepository,
                         TraxModuleRepository traxModuleRepository,
                         RideRecordRepository rideRecordRepository,
                         RidePointRepository ridePointRepository,
                         HistoryBicycleRepository historyBicycleRepository,
                         HistoryRideRecordRepository historyRideRecordRepository,
                         HistoryRidePointRepository historyRidePointRepository,
                         ModuleTelemetryWebSocketHandler telemetryWs,
                         ModuleImuWebSocketHandler imuWs) {
        this.bicycleRepository = bicycleRepository;
        this.userRepository = userRepository;
        this.bikeModelRepository = bikeModelRepository;
        this.traxModuleRepository = traxModuleRepository;
        this.rideRecordRepository = rideRecordRepository;
        this.ridePointRepository = ridePointRepository;
        this.historyBicycleRepository = historyBicycleRepository;
        this.historyRideRecordRepository = historyRideRecordRepository;
        this.historyRidePointRepository = historyRidePointRepository;
        this.telemetryWs = telemetryWs;
        this.imuWs = imuWs;
    }

    public BicycleDto createBike(Long userId, BicycleDto dto) {
        Bicycle bicycle = new Bicycle();
        mapDtoToBicycle(dto, bicycle);

        User owner = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));
        bicycle.setOwner(owner);

        if (dto.getModelName() != null && dto.getModelBrand() != null) {
            BikeModel model = bikeModelRepository.findByModelNameAndBrand_Name(
                    dto.getModelName(), dto.getModelBrand())
                    .orElse(null);
            bicycle.setModel(model);
        }

        // Bind TRA-X module if provided
        if (dto.getTraxSerialNumber() != null && !dto.getTraxSerialNumber().isEmpty()) {
            // P0a: enforce serial uniqueness at the bicycles table — the
            // trax_module registry path below only fires when the module is
            // pre-registered, but the serial is still written via
            // mapDtoToBicycle regardless. Without this guard two bikes can
            // claim the same serial and the WS handshake query throws
            // NonUniqueResultException → "Connecting…" forever.
            // Bike has not been persisted yet — any existing row with this
            // serial is by definition another bike.
            boolean taken = !bicycleRepository.findByTraxSerialNumber(dto.getTraxSerialNumber()).isEmpty();
            if (taken) {
                throw new IllegalStateException(
                        "Module " + dto.getTraxSerialNumber() + " is already bound to another bike");
            }
            Optional<TraxModule> module = traxModuleRepository.findBySerialNo(dto.getTraxSerialNumber());
            if (module.isPresent()) {
                TraxModule m = module.get();
                // P0a: reject duplicate binding so two bikes (potentially owned
                // by different users) cannot share the same module SN — prevents
                // telemetry cross-leakage and ride-attribution mix-ups.
                if (m.isBound()) {
                    throw new IllegalStateException(
                            "Module " + dto.getTraxSerialNumber() + " is already bound to another bike");
                }
                bicycle.setModule(m);
                m.setBound(true);
                m.setBoundAt(LocalDateTime.now()); // P1: telemetry read filter boundary
                traxModuleRepository.save(m);
            }
        }

        bicycle = bicycleRepository.save(bicycle);
        return BicycleDto.fromBicycle(bicycle);
    }

    public BicycleDto updateBike(Long bikeId, Long userId, BicycleDto dto) {
        Bicycle bicycle = bicycleRepository.findById(bikeId)
                .orElseThrow(() -> new IllegalArgumentException("Bike not found"));

        if (!bicycle.getOwner().getId().equals(userId)) {
            throw new IllegalArgumentException("Unauthorized: You do not own this bike");
        }

        String oldTraxSerialNumber = bicycle.getTraxSerialNumber();

        mapDtoToBicycle(dto, bicycle);

        if (dto.getModelName() != null && dto.getModelBrand() != null) {
            BikeModel model = bikeModelRepository.findByModelNameAndBrand_Name(
                    dto.getModelName(), dto.getModelBrand())
                    .orElse(null);
            bicycle.setModel(model);
        }

        // Handle module binding: unbind old and bind new if changed
        String newTraxSerialNumber = dto.getTraxSerialNumber();
        if (oldTraxSerialNumber != null && !oldTraxSerialNumber.isEmpty() &&
                (newTraxSerialNumber == null || newTraxSerialNumber.isEmpty() ||
                        !oldTraxSerialNumber.equals(newTraxSerialNumber))) {
            // Unbind old module
            Optional<TraxModule> oldModule = traxModuleRepository.findBySerialNo(oldTraxSerialNumber);
            if (oldModule.isPresent()) {
                oldModule.get().setBound(false);
                oldModule.get().setBoundAt(null);
                traxModuleRepository.save(oldModule.get());
            }
            bicycle.setModule(null);
            // Kick any live WS subscribers — the old owner must not continue to
            // receive telemetry for a module that’s no longer theirs.
            telemetryWs.closeSerial(oldTraxSerialNumber);
            imuWs.closeSerial(oldTraxSerialNumber);
        }

        if (newTraxSerialNumber != null && !newTraxSerialNumber.isEmpty() &&
                (oldTraxSerialNumber == null || oldTraxSerialNumber.isEmpty() ||
                        !oldTraxSerialNumber.equals(newTraxSerialNumber))) {
            // P0a: bicycles-table uniqueness guard — see createBike.
            final Long currentBikeId = bicycle.getId();
            boolean taken = bicycleRepository.findByTraxSerialNumber(newTraxSerialNumber).stream()
                    .anyMatch(b -> !currentBikeId.equals(b.getId()));
            if (taken) {
                throw new IllegalStateException(
                        "Module " + newTraxSerialNumber + " is already bound to another bike");
            }
            // Bind new module
            Optional<TraxModule> newModule = traxModuleRepository.findBySerialNo(newTraxSerialNumber);
            if (newModule.isPresent()) {
                TraxModule m = newModule.get();
                if (m.isBound()) {
                    throw new IllegalStateException(
                            "Module " + newTraxSerialNumber + " is already bound to another bike");
                }
                m.setBound(true);
                m.setBoundAt(LocalDateTime.now());
                traxModuleRepository.save(m);
                bicycle.setModule(m);
            }
        }

        bicycle = bicycleRepository.save(bicycle);
        return BicycleDto.fromBicycle(bicycle);
    }

    public void deleteBike(Long bikeId, Long userId) {
        Bicycle bicycle = bicycleRepository.findById(bikeId)
                .orElseThrow(() -> new IllegalArgumentException("Bike not found"));

        if (!bicycle.getOwner().getId().equals(userId)) {
            throw new IllegalArgumentException("Unauthorized: You do not own this bike");
        }

        // 1. Archive bicycle to history
        HistoryBicycle historyBike = historyBicycleRepository.save(
                HistoryBicycle.fromBicycle(bicycle));

        // 2. Archive all ride records and their points
        List<RideRecord> rides = rideRecordRepository.findByBicycleId(bikeId);
        for (RideRecord ride : rides) {
            HistoryRideRecord historyRide = historyRideRecordRepository.save(
                    HistoryRideRecord.fromRideRecord(ride, historyBike.getId()));

            List<RidePoint> points = ridePointRepository.findByRideId(ride.getId());
            List<HistoryRidePoint> historyPoints = points.stream()
                    .map(p -> HistoryRidePoint.fromRidePoint(p, historyRide.getId()))
                    .toList();
            historyRidePointRepository.saveAll(historyPoints);

            ridePointRepository.deleteByRideId(ride.getId());
            rideRecordRepository.delete(ride);
        }

        // 3. Unbind TRA-X module if present
        if (bicycle.getTraxSerialNumber() != null && !bicycle.getTraxSerialNumber().isEmpty()) {
            Optional<TraxModule> module = traxModuleRepository.findBySerialNo(bicycle.getTraxSerialNumber());
            if (module.isPresent()) {
                module.get().setBound(false);
                module.get().setBoundAt(null);
                traxModuleRepository.save(module.get());
            }
            telemetryWs.closeSerial(bicycle.getTraxSerialNumber());
            imuWs.closeSerial(bicycle.getTraxSerialNumber());
        }

        // 4. Delete original bicycle
        bicycleRepository.delete(bicycle);
    }

    public List<BicycleDto> getUserBikes(Long userId) {
        return bicycleRepository.findByOwnerIdOrderByCreatedAtDesc(userId)
                .stream()
                .map(BicycleDto::fromBicycle)
                .collect(Collectors.toList());
    }

    public BicycleDto getBikeById(Long bikeId, Long userId) {
        Bicycle bicycle = bicycleRepository.findById(bikeId)
                .orElseThrow(() -> new IllegalArgumentException("Bike not found"));

        if (!bicycle.getOwner().getId().equals(userId)) {
            throw new IllegalArgumentException("Unauthorized: You do not own this bike");
        }

        return BicycleDto.fromBicycle(bicycle);
    }

    private void mapDtoToBicycle(BicycleDto dto, Bicycle bicycle) {
        bicycle.setName(dto.getName());
        bicycle.setMotor(dto.getMotor());
        bicycle.setController(dto.getController());
        bicycle.setBattery(dto.getBattery());
        bicycle.setOther(dto.getOther());
        bicycle.setImageUrl(dto.getImageUrl());
        bicycle.setTraxSerialNumber(dto.getTraxSerialNumber());
        bicycle.setMotorCertified(dto.isMotorCertified());
        bicycle.setControllerCertified(dto.isControllerCertified());
        bicycle.setBatteryCertified(dto.isBatteryCertified());
    }
}
