package com.trax.service;

import com.trax.dto.TrailCreateRequest;
import com.trax.dto.TrailDto;
import com.trax.model.Trail;
import com.trax.model.TrailPoint;
import com.trax.model.User;
import com.trax.repository.TrailPointRepository;
import com.trax.repository.TrailRepository;
import com.trax.repository.UserRepository;
import com.trax.util.GeoUtils;
import com.trax.util.LapDetector;
import com.trax.util.TrailOptimizer;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@Transactional
public class TrailService {
    private final TrailRepository trailRepository;
    private final TrailPointRepository trailPointRepository;
    private final UserRepository userRepository;

    public TrailService(TrailRepository trailRepository, TrailPointRepository trailPointRepository, UserRepository userRepository) {
        this.trailRepository = trailRepository;
        this.trailPointRepository = trailPointRepository;
        this.userRepository = userRepository;
    }

    public List<Trail> getTrailsByOwner(Long userId) {
        return trailRepository.findByCreatorIdAndDeletedFalse(userId);
    }

    public List<TrailDto> getVisibleTrails(Long userId) {
        List<Trail> trails = trailRepository.findVisibleTrails(userId);
        // Batch load creators
        List<Long> creatorIds = trails.stream()
                .map(Trail::getCreatorId)
                .distinct()
                .collect(Collectors.toList());
        Map<Long, User> creatorMap = userRepository.findAllById(creatorIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));
        return trails.stream()
                .map(t -> TrailDto.fromEntity(t, creatorMap.get(t.getCreatorId())))
                .toList();
    }

    public Trail getTrailById(Long id) {
        return trailRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Trail not found"));
    }

    public Trail createTrail(Trail trail) {
        return trailRepository.save(trail);
    }

    public Trail updateTrail(Long id, Trail updated) {
        Trail trail = getTrailById(id);
        trail.setName(updated.getName());
        trail.setLocation(updated.getLocation());
        trail.setDifficulty(updated.getDifficulty());
        trail.setDescription(updated.getDescription());
        trail.setDistance(updated.getDistance());
        trail.setElevation(updated.getElevation());
        return trailRepository.save(trail);
    }

    public Trail updateTrailVisibility(Long id, Long userId, boolean isPublic) {
        Trail trail = getTrailById(id);
        if (!trail.getCreatorId().equals(userId)) {
            throw new IllegalArgumentException("Only the trail owner can change visibility");
        }
        trail.setPublic(isPublic);
        return trailRepository.save(trail);
    }

    public void deleteTrail(Long id, Long userId) {
        Trail trail = getTrailById(id);
        if (!trail.getCreatorId().equals(userId)) {
            throw new IllegalArgumentException("Only the trail owner can delete this trail");
        }
        trail.setDeleted(true);
        trailRepository.save(trail);
    }

    public TrailDto createTrailFromRecording(Long userId, TrailCreateRequest request) {
        if (request.getPoints() == null || request.getPoints().size() < 2) {
            throw new IllegalArgumentException("At least 2 points are required to create a trail");
        }

        // Build raw TrailPoint list
        List<TrailPoint> rawPoints = new ArrayList<>();
        for (int i = 0; i < request.getPoints().size(); i++) {
            TrailCreateRequest.TrailPointData pd = request.getPoints().get(i);
            TrailPoint tp = new TrailPoint();
            tp.setLatitude(pd.getLatitude());
            tp.setLongitude(pd.getLongitude());
            tp.setAltitude(pd.getAltitude());
            tp.setSequenceIndex(i);
            tp.setTimestamp(pd.getTimestamp() != null
                    ? LocalDateTime.parse(pd.getTimestamp())
                    : LocalDateTime.now());
            rawPoints.add(tp);
        }

        // Optimize points
        List<TrailPoint> optimized = TrailOptimizer.optimizePoints(rawPoints);
        if (optimized.size() < 2) {
            throw new IllegalArgumentException("Not enough valid points after optimization");
        }

        TrailPoint first = optimized.get(0);
        TrailPoint last = optimized.get(optimized.size() - 1);

        // Auto-detect type: lap or free_ride
        boolean isLap = LapDetector.isLapComplete(
                first.getLatitude(), first.getLongitude(),
                last.getLatitude(), last.getLongitude(),
                optimized);
        String detectedType;
        if (isLap) {
            detectedType = "lap";
            LapDetector.snapToLap(optimized);
        } else {
            detectedType = "free_ride";
        }

        // Calculate distance and elevation
        double totalDistKm = 0;
        double totalElevGain = 0;
        for (int i = 1; i < optimized.size(); i++) {
            TrailPoint prev = optimized.get(i - 1);
            TrailPoint curr = optimized.get(i);
            totalDistKm += GeoUtils.haversineKm(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
            double altDiff = curr.getAltitude() - prev.getAltitude();
            if (altDiff > 0) totalElevGain += altDiff;
        }

        // Create Trail
        Trail trail = new Trail();
        trail.setName(request.getName());
        trail.setType(detectedType);
        trail.setDifficulty(request.getDifficulty() != null ? request.getDifficulty() : "medium");
        trail.setLocation(request.getLocation());
        trail.setPublic(request.isPublic());
        trail.setCreatorId(userId);
        trail.setDistance(Math.round(totalDistKm * 100.0) / 100.0);
        trail.setElevation(Math.round(totalElevGain * 10.0) / 10.0);
        trail.setStartLatitude(first.getLatitude());
        trail.setStartLongitude(first.getLongitude());
        trail.setEndLatitude(last.getLatitude());
        trail.setEndLongitude(last.getLongitude());
        // Generate a Google Static Maps thumbnail URL so trail cards render
        // a real preview of the route immediately.
        trail.setImageUrl(com.trax.util.StaticMapUrlBuilder.forTrailPoints(optimized));
        trail = trailRepository.save(trail);

        // Save optimized points
        for (TrailPoint tp : optimized) {
            tp.setTrail(trail);
        }
        trailPointRepository.saveAll(optimized);

        return TrailDto.fromEntity(trail);
    }

    public List<TrailPoint> getTrailPoints(Long trailId) {
        return trailPointRepository.findByTrailIdOrderBySequenceIndexAsc(trailId);
    }
}
