package com.trax.service;

import com.trax.dto.ModuleTelemetryDto;
import com.trax.model.RidePoint;
import com.trax.model.RideRecord;
import com.trax.model.TrailPoint;
import com.trax.model.TraxModule;
import com.trax.repository.RidePointRepository;
import com.trax.repository.RideRecordRepository;
import com.trax.repository.TrailPointRepository;
import com.trax.repository.TraxModuleRepository;
import com.trax.util.GeoUtils;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.*;

@Service
public class ModuleSimulatorService {
    /** Module-to-server upload cadence (Hz, seconds between packets). */
    private static final long TICK_SECONDS = 1L;

    private final ModuleTelemetryService telemetryService;
    private final TraxModuleRepository moduleRepository;
    private final RideRecordRepository rideRecordRepository;
    private final RidePointRepository ridePointRepository;
    private final TrailPointRepository trailPointRepository;
    private final RouteService routeService;
    private final ControllerTelemetrySimulator controllerSimulator;
    private final ScheduledExecutorService executor = Executors.newScheduledThreadPool(4);
    private final Map<String, ScheduledFuture<?>> activeSimulations = new ConcurrentHashMap<>();
    private final Map<String, double[]> simulationState = new ConcurrentHashMap<>();
    private final Set<String> pausedSimulations = ConcurrentHashMap.newKeySet();
    private final Map<String, Long> simulationRideIds = new ConcurrentHashMap<>();

    // Route-following state
    private final Map<String, List<double[]>> simulationRoutes = new ConcurrentHashMap<>();
    private final Map<String, double[]> routeProgress = new ConcurrentHashMap<>();
    // routeProgress value: [segmentIndex, fractionAlongSegment]
    private final Set<String> fetchingNextRoute = ConcurrentHashMap.newKeySet();
    // Track which simulations use a looping trail route (no continuation fetch)
    private final Set<String> trailLoopSimulations = ConcurrentHashMap.newKeySet();
    // For trail loops: the segment index where looping starts (skips approach from user position)
    private final Map<String, Integer> simulationLoopStart = new ConcurrentHashMap<>();

    public ModuleSimulatorService(ModuleTelemetryService telemetryService,
                                  TraxModuleRepository moduleRepository,
                                  RideRecordRepository rideRecordRepository,
                                  RidePointRepository ridePointRepository,
                                  TrailPointRepository trailPointRepository,
                                  RouteService routeService,
                                  ControllerTelemetrySimulator controllerSimulator) {
        this.telemetryService = telemetryService;
        this.moduleRepository = moduleRepository;
        this.rideRecordRepository = rideRecordRepository;
        this.ridePointRepository = ridePointRepository;
        this.trailPointRepository = trailPointRepository;
        this.routeService = routeService;
        this.controllerSimulator = controllerSimulator;
    }

    public void startSimulation(String serialNo, Double latitude, Double longitude, Long rideId) {
        moduleRepository.findBySerialNo(serialNo)
                .orElseThrow(() -> new IllegalArgumentException("Module not found: " + serialNo));

        if (activeSimulations.containsKey(serialNo)) {
            // Stop the old simulation before starting a new one
            stopSimulation(serialNo);
        }

        // Use provided location or default to LA
        double startLat = latitude != null ? latitude : 34.0522;
        double startLng = longitude != null ? longitude : -118.2437;

        // State: [lat, lng, direction_radians, battery_percent, tick_count, current_speed_kmh]
        double[] state = {startLat, startLng, Math.random() * 2 * Math.PI, 100.0, 0, 0.0};
        simulationState.put(serialNo, state);
        pausedSimulations.remove(serialNo);
        if (rideId != null) {
            simulationRideIds.put(serialNo, rideId);
        }

        // If the ride is a lap-timer ride (has a trail), use the trail route and loop
        boolean usingTrailRoute = false;
        if (rideId != null) {
            try {
                RideRecord ride = rideRecordRepository.findById(rideId).orElse(null);
                if (ride != null && ride.getTrail() != null) {
                    List<TrailPoint> trailPts = trailPointRepository
                            .findByTrailIdOrderBySequenceIndexAsc(ride.getTrail().getId());
                    if (trailPts.size() >= 2) {
                        // Build trail loop points
                        List<double[]> trailRoute = new java.util.ArrayList<>();
                        for (TrailPoint tp : trailPts) {
                            trailRoute.add(new double[]{tp.getLatitude(), tp.getLongitude()});
                        }

                        // Find nearest trail segment to the user's current position
                        int nearestSeg = 0;
                        double nearestDist = Double.MAX_VALUE;
                        for (int i = 0; i < trailRoute.size(); i++) {
                            double d = GeoUtils.haversineKm(startLat, startLng,
                                    trailRoute.get(i)[0], trailRoute.get(i)[1]);
                            if (d < nearestDist) {
                                nearestDist = d;
                                nearestSeg = i;
                            }
                        }

                        // Build route: user position → nearest trail point → rest of trail → loop
                        List<double[]> route = new java.util.ArrayList<>();
                        route.add(new double[]{startLat, startLng}); // start from user's location
                        // Add trail points starting from nearest, wrapping around to cover full loop
                        for (int i = 0; i < trailRoute.size(); i++) {
                            int idx = (nearestSeg + i) % trailRoute.size();
                            route.add(trailRoute.get(idx));
                        }
                        // Close back to the start of the trail loop for seamless looping
                        route.add(trailRoute.get(nearestSeg));

                        simulationRoutes.put(serialNo, route);
                        routeProgress.put(serialNo, new double[]{0, 0.0});
                        trailLoopSimulations.add(serialNo);
                        // Keep state at user's actual position (not trail start)
                        state[0] = startLat;
                        state[1] = startLng;
                        // Store the loop start index (after the approach segment)
                        // so looping skips the initial approach from user position
                        simulationLoopStart.put(serialNo, 1); // index 1 = first trail point
                        usingTrailRoute = true;
                        System.out.println("ModuleSimulator: using trail route (" + trailPts.size()
                                + " pts, loop mode, starting from user pos → nearest pt " + nearestSeg
                                + ") for " + serialNo);
                    }
                }
            } catch (Exception e) {
                System.err.println("Failed to load trail route for ride " + rideId + ": " + e.getMessage());
            }
        }

        // Fallback: fetch a road route from Google Directions API
        if (!usingTrailRoute) {
            try {
                List<double[]> route = routeService.fetchRoute(startLat, startLng);
                if (route != null && route.size() >= 2) {
                    simulationRoutes.put(serialNo, route);
                    routeProgress.put(serialNo, new double[]{0, 0.0});
                    state[0] = route.get(0)[0];
                    state[1] = route.get(0)[1];
                }
            } catch (Exception e) {
                System.err.println("Failed to fetch route for " + serialNo + ", using random walk: " + e.getMessage());
            }
        }

        if (rideId != null) controllerSimulator.resetRide(rideId);

        ScheduledFuture<?> future = executor.scheduleAtFixedRate(() -> {
            try {
                generateTick(serialNo);
            } catch (Exception e) {
                System.err.println("Simulator error for " + serialNo + ": " + e.getMessage());
            }
        }, 0, TICK_SECONDS, TimeUnit.SECONDS);

        activeSimulations.put(serialNo, future);
    }

    public void pauseSimulation(String serialNo) {
        if (activeSimulations.containsKey(serialNo)) {
            pausedSimulations.add(serialNo);
        }
    }

    public void resumeSimulation(String serialNo) {
        pausedSimulations.remove(serialNo);
    }

    public void stopSimulation(String serialNo) {
        ScheduledFuture<?> future = activeSimulations.remove(serialNo);
        if (future != null) {
            future.cancel(false);
        }
        Long rideId = simulationRideIds.remove(serialNo);
        if (rideId != null) controllerSimulator.resetRide(rideId);
        simulationState.remove(serialNo);
        pausedSimulations.remove(serialNo);
        simulationRoutes.remove(serialNo);
        routeProgress.remove(serialNo);
        fetchingNextRoute.remove(serialNo);
        trailLoopSimulations.remove(serialNo);
        simulationLoopStart.remove(serialNo);
    }

    public boolean isSimulating(String serialNo) {
        return activeSimulations.containsKey(serialNo);
    }

    private void generateTick(String serialNo) {
        // Skip tick if paused
        if (pausedSimulations.contains(serialNo)) return;

        double[] s = simulationState.get(serialNo);
        if (s == null) return;

        List<double[]> route = simulationRoutes.get(serialNo);
        if (route != null) {
            generateRouteFollowingTick(serialNo, s, route);
        } else {
            generateRandomWalkTick(serialNo, s);
        }
    }

    /**
     * Advance along the pre-fetched road route based on simulated speed.
     * Accumulates distance traveled per tick and interpolates between route points.
     */
    private void generateRouteFollowingTick(String serialNo, double[] s, List<double[]> route) {
        double[] progress = routeProgress.get(serialNo);
        if (progress == null) return;

        int segIndex = (int) progress[0];
        double fraction = progress[1];

        // Pre-fetch next route when we are within last 20% of current route
        // (only for non-trail routes; trail routes loop instead)
        if (!trailLoopSimulations.contains(serialNo)
                && segIndex > route.size() * 0.8 && !fetchingNextRoute.contains(serialNo)) {
            fetchingNextRoute.add(serialNo);
            final double endLat = route.get(route.size() - 1)[0];
            final double endLng = route.get(route.size() - 1)[1];
            executor.submit(() -> {
                try {
                    List<double[]> next = routeService.fetchRoute(endLat, endLng);
                    if (next != null && next.size() >= 2 && simulationRoutes.containsKey(serialNo)) {
                        // Append next route to current route (skip first point to avoid dup)
                        List<double[]> combined = new java.util.ArrayList<>(simulationRoutes.get(serialNo));
                        combined.addAll(next.subList(1, next.size()));
                        simulationRoutes.put(serialNo, combined);
                        System.out.println("ModuleSimulator: appended " + (next.size() - 1)
                                + " continuation points for " + serialNo);
                    }
                } catch (Exception e) {
                    System.err.println("Failed to fetch continuation route: " + e.getMessage());
                } finally {
                    fetchingNextRoute.remove(serialNo);
                }
            });
        }

        // If we've reached the end of the route
        if (segIndex >= route.size() - 1) {
            if (trailLoopSimulations.contains(serialNo)) {
                // Loop back to the trail loop start (skipping the initial approach segment)
                int loopStart = simulationLoopStart.getOrDefault(serialNo, 0);
                segIndex = loopStart;
                fraction = 0.0;
                progress[0] = loopStart;
                progress[1] = 0.0;
            } else {
                // Hold at the last point for non-trail routes
                emitTelemetry(serialNo, s, 0.0);
                return;
            }
        }

        // Simulate speed (same realistic eBike distribution)
        double prevSpeed = s[5];
        double targetSpeed;
        double rand = ThreadLocalRandom.current().nextDouble();
        if (rand < 0.05) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(5, 15);
        } else if (rand < 0.15) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(15, 25);
        } else if (rand < 0.85) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(20, 45);
        } else {
            targetSpeed = ThreadLocalRandom.current().nextDouble(35, 60);
        }
        double speed = prevSpeed + (targetSpeed - prevSpeed) * 0.7;
        speed = Math.max(0, speed);
        s[5] = speed;

        // Distance to travel in this tick (km)
        double remaining = speed / 3600.0 * TICK_SECONDS;
        boolean isLoop = trailLoopSimulations.contains(serialNo);

        // Walk along route segments, consuming distance
        int loopGuard = route.size() * 2; // prevent infinite loops
        int loopStartIdx = simulationLoopStart.getOrDefault(serialNo, 0);
        while (remaining > 0 && loopGuard-- > 0) {
            if (segIndex >= route.size() - 1) {
                if (isLoop) {
                    segIndex = loopStartIdx;
                    fraction = 0.0;
                } else {
                    break;
                }
            }
            double[] from = route.get(segIndex);
            double[] to = route.get(segIndex + 1);
            double segLen = GeoUtils.haversineKm(from[0], from[1], to[0], to[1]);

            // Distance left in current segment from current fraction
            double segRemaining = segLen * (1.0 - fraction);

            if (remaining < segRemaining) {
                // We stop partway through this segment
                fraction += (remaining / segLen);
                remaining = 0;
            } else {
                // Consume rest of this segment and move to next
                remaining -= segRemaining;
                segIndex++;
                fraction = 0.0;
            }
        }

        // Clamp for non-loop routes
        if (!isLoop && segIndex >= route.size() - 1) {
            segIndex = route.size() - 1;
            fraction = 0.0;
        }

        // Interpolate position
        double lat, lng;
        if (segIndex < route.size() - 1) {
            double[] from = route.get(segIndex);
            double[] to = route.get(segIndex + 1);
            lat = from[0] + (to[0] - from[0]) * fraction;
            lng = from[1] + (to[1] - from[1]) * fraction;
        } else {
            lat = route.get(segIndex)[0];
            lng = route.get(segIndex)[1];
        }

        // Update progress
        progress[0] = segIndex;
        progress[1] = fraction;

        // Update state position
        s[0] = lat;
        s[1] = lng;

        emitTelemetry(serialNo, s, speed);
    }

    /**
     * Original random-walk logic (fallback when route is unavailable).
     */
    private void generateRandomWalkTick(String serialNo, double[] s) {
        double prevSpeed = s[5];
        double targetSpeed;

        double rand = ThreadLocalRandom.current().nextDouble();
        if (rand < 0.05) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(5, 15);
        } else if (rand < 0.15) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(15, 25);
        } else if (rand < 0.85) {
            targetSpeed = ThreadLocalRandom.current().nextDouble(20, 45);
        } else {
            targetSpeed = ThreadLocalRandom.current().nextDouble(35, 60);
        }

        double speed = prevSpeed + (targetSpeed - prevSpeed) * 0.7;
        speed = Math.max(0, speed);
        s[5] = speed;

        double stepKm = speed / 3600.0 * TICK_SECONDS;
        double direction = s[2] + (ThreadLocalRandom.current().nextDouble() - 0.5) * 0.3;
        double dLat = stepKm / 111.32 * Math.cos(direction);
        double dLng = stepKm / (111.32 * Math.cos(Math.toRadians(s[0]))) * Math.sin(direction);

        s[0] += dLat;
        s[1] += dLng;
        s[2] = direction;

        emitTelemetry(serialNo, s, speed);
    }

    /**
     * Start a race simulation that doesn't require a real module.
     * Follows the trail route and writes RidePoints directly.
     */
    public void startRaceSimulation(Long rideId, Double latitude, Double longitude) {
        String simKey = "race_ride_" + rideId;

        if (activeSimulations.containsKey(simKey)) {
            stopSimulation(simKey);
        }

        double startLat = latitude != null ? latitude : 22.8956;
        double startLng = longitude != null ? longitude : 113.8739;

        double[] state = {startLat, startLng, Math.random() * 2 * Math.PI, 100.0, 0, 0.0};
        simulationState.put(simKey, state);
        pausedSimulations.remove(simKey);
        simulationRideIds.put(simKey, rideId);

        // Load trail route from the ride's trail
        boolean usingTrailRoute = false;
        try {
            RideRecord ride = rideRecordRepository.findById(rideId).orElse(null);
            if (ride != null && ride.getTrail() != null) {
                List<TrailPoint> trailPts = trailPointRepository
                        .findByTrailIdOrderBySequenceIndexAsc(ride.getTrail().getId());
                if (trailPts.size() >= 2) {
                    List<double[]> trailRoute = new java.util.ArrayList<>();
                    for (TrailPoint tp : trailPts) {
                        trailRoute.add(new double[]{tp.getLatitude(), tp.getLongitude()});
                    }

                    int nearestSeg = 0;
                    double nearestDist = Double.MAX_VALUE;
                    for (int i = 0; i < trailRoute.size(); i++) {
                        double d = GeoUtils.haversineKm(startLat, startLng,
                                trailRoute.get(i)[0], trailRoute.get(i)[1]);
                        if (d < nearestDist) {
                            nearestDist = d;
                            nearestSeg = i;
                        }
                    }

                    List<double[]> route = new java.util.ArrayList<>();
                    route.add(new double[]{startLat, startLng});
                    for (int i = 0; i < trailRoute.size(); i++) {
                        int idx = (nearestSeg + i) % trailRoute.size();
                        route.add(trailRoute.get(idx));
                    }
                    route.add(trailRoute.get(nearestSeg));

                    simulationRoutes.put(simKey, route);
                    routeProgress.put(simKey, new double[]{0, 0.0});
                    trailLoopSimulations.add(simKey);
                    simulationLoopStart.put(simKey, 1);
                    usingTrailRoute = true;
                }
            }
        } catch (Exception e) {
            System.err.println("Failed to load trail for race sim ride " + rideId + ": " + e.getMessage());
        }

        if (!usingTrailRoute) {
            try {
                List<double[]> route = routeService.fetchRoute(startLat, startLng);
                if (route != null && route.size() >= 2) {
                    simulationRoutes.put(simKey, route);
                    routeProgress.put(simKey, new double[]{0, 0.0});
                    state[0] = route.get(0)[0];
                    state[1] = route.get(0)[1];
                }
            } catch (Exception e) {
                System.err.println("Failed to fetch route for race sim: " + e.getMessage());
            }
        }

        controllerSimulator.resetRide(rideId);

        ScheduledFuture<?> future = executor.scheduleAtFixedRate(() -> {
            try {
                generateTick(simKey);
            } catch (Exception e) {
                System.err.println("Race simulator error for ride " + rideId + ": " + e.getMessage());
            }
        }, 0, TICK_SECONDS, TimeUnit.SECONDS);

        activeSimulations.put(simKey, future);
        System.out.println("ModuleSimulator: started race simulation for ride " + rideId);
    }

    /**
     * Emit telemetry + ride point for the current tick.
     */
    private void emitTelemetry(String simKey, double[] s, double speed) {
        s[3] = Math.max(0, s[3] - 0.05); // battery drain
        s[4]++;

        int battery = (int) Math.round(s[3]);
        int signal = ThreadLocalRandom.current().nextInt(70, 101);

        // Only record module telemetry for real modules (not race simulations)
        if (!simKey.startsWith("race_ride_")) {
            ModuleTelemetryDto dto = new ModuleTelemetryDto();
            dto.setLatitude(s[0]);
            dto.setLongitude(s[1]);
            dto.setSpeed(Math.round(speed * 10.0) / 10.0);
            dto.setBatteryPercent(battery);
            dto.setSignalStrength(signal);
            try {
                telemetryService.recordTelemetry(simKey, dto);
            } catch (Exception e) {
                // Ignore telemetry errors
            }
        }

        // Save as RidePoint
        Long rideId = simulationRideIds.get(simKey);
        if (rideId != null) {
            final double finalSpeed = Math.round(speed * 10.0) / 10.0;
            final double finalLat = s[0];
            final double finalLng = s[1];
            final LocalDateTime ts = LocalDateTime.now();
            final String key = simKey;
            rideRecordRepository.findById(rideId).ifPresent(ride -> {
                RidePoint point = new RidePoint();
                point.setRide(ride);
                point.setLatitude(finalLat);
                point.setLongitude(finalLng);
                point.setSpeed(finalSpeed);
                point.setAltitude(0.0);
                point.setTimestamp(ts);
                RidePoint saved = ridePointRepository.save(point);

                // Time-aligned controller telemetry packet (1 Hz, same timestamp).
                TraxModule mod = key.startsWith("race_ride_")
                        ? null
                        : moduleRepository.findBySerialNo(key).orElse(null);
                boolean raceMode = key.startsWith("race_ride_")
                        || "race".equalsIgnoreCase(ride.getSource());
                try {
                    controllerSimulator.simulateAndPersist(
                            ride, saved, mod, finalSpeed, (double) TICK_SECONDS, raceMode);
                } catch (Exception e) {
                    System.err.println("Controller telemetry sim failed: " + e.getMessage());
                }
            });
        }
    }
}
