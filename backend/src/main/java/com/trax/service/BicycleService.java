package com.trax.service;

import com.trax.dto.BicycleDto;
import com.trax.model.*;
import com.trax.repository.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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

    public BicycleService(BicycleRepository bicycleRepository,
                         UserRepository userRepository,
                         BikeModelRepository bikeModelRepository,
                         TraxModuleRepository traxModuleRepository,
                         RideRecordRepository rideRecordRepository,
                         RidePointRepository ridePointRepository,
                         HistoryBicycleRepository historyBicycleRepository,
                         HistoryRideRecordRepository historyRideRecordRepository,
                         HistoryRidePointRepository historyRidePointRepository) {
        this.bicycleRepository = bicycleRepository;
        this.userRepository = userRepository;
        this.bikeModelRepository = bikeModelRepository;
        this.traxModuleRepository = traxModuleRepository;
        this.rideRecordRepository = rideRecordRepository;
        this.ridePointRepository = ridePointRepository;
        this.historyBicycleRepository = historyBicycleRepository;
        this.historyRideRecordRepository = historyRideRecordRepository;
        this.historyRidePointRepository = historyRidePointRepository;
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
            Optional<TraxModule> module = traxModuleRepository.findBySerialNo(dto.getTraxSerialNumber());
            if (module.isPresent()) {
                bicycle.setModule(module.get());
                module.get().setBound(true);
                traxModuleRepository.save(module.get());
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
                traxModuleRepository.save(oldModule.get());
            }
            bicycle.setModule(null);
        }

        if (newTraxSerialNumber != null && !newTraxSerialNumber.isEmpty() &&
                (oldTraxSerialNumber == null || oldTraxSerialNumber.isEmpty() ||
                        !oldTraxSerialNumber.equals(newTraxSerialNumber))) {
            // Bind new module
            Optional<TraxModule> newModule = traxModuleRepository.findBySerialNo(newTraxSerialNumber);
            if (newModule.isPresent()) {
                newModule.get().setBound(true);
                traxModuleRepository.save(newModule.get());
                bicycle.setModule(newModule.get());
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
                traxModuleRepository.save(module.get());
            }
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
