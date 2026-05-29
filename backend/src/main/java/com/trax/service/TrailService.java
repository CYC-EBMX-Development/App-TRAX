package com.trax.service;

import com.trax.dto.TrailCreateRequest;
import com.trax.dto.TrailDto;
import com.trax.model.Trail;
import com.trax.model.TrailPoint;
import com.trax.model.User;
import com.trax.repository.RaceRepository;
import com.trax.repository.RideRecordRepository;
import com.trax.repository.TrailPointRepository;
import com.trax.repository.TrailRepository;
import com.trax.repository.UserCheckpointRepository;
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
    private final TrailThumbnailService trailThumbnailService;
    private final RideRecordRepository rideRecordRepository;
    private final RaceRepository raceRepository;
    private final UserCheckpointRepository userCheckpointRepository;

    public TrailService(TrailRepository trailRepository,
                        TrailPointRepository trailPointRepository,
                        UserRepository userRepository,
                        TrailThumbnailService trailThumbnailService,
                        RideRecordRepository rideRecordRepository,
                        RaceRepository raceRepository,
                        UserCheckpointRepository userCheckpointRepository) {
        this.trailRepository = trailRepository;
        this.trailPointRepository = trailPointRepository;
        this.userRepository = userRepository;
        this.trailThumbnailService = trailThumbnailService;
        this.rideRecordRepository = rideRecordRepository;
        this.raceRepository = raceRepository;
        this.userCheckpointRepository = userCheckpointRepository;
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
        // Hard-delete only when no ride/race references this trail.
        // (HistoryRideRecord stores trailId as a plain Long without FK, so
        //  archived rides keep their dangling reference \u2014 acceptable.)
        long rideRefs = rideRecordRepository.countByTrailId(id);
        long raceRefs = raceRepository.countByTrailId(id);
        if (rideRefs == 0 && raceRefs == 0) {
            // Owned children must go too \u2014 user_checkpoints has FK NOT NULL.
            userCheckpointRepository.deleteByTrailId(id);
            trailPointRepository.deleteByTrailId(id);
            trailRepository.delete(trail);
            return;
        }
        // Soft-delete: keep the row so historical rides/races still resolve.
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
        double minAlt = Double.POSITIVE_INFINITY;
        double maxAlt = Double.NEGATIVE_INFINITY;
        for (int i = 0; i < optimized.size(); i++) {
            TrailPoint curr = optimized.get(i);
            double a = curr.getAltitude();
            if (a < minAlt) minAlt = a;
            if (a > maxAlt) maxAlt = a;
            if (i == 0) continue;
            TrailPoint prev = optimized.get(i - 1);
            totalDistKm += GeoUtils.haversineKm(
                    prev.getLatitude(), prev.getLongitude(),
                    curr.getLatitude(), curr.getLongitude());
            double altDiff = curr.getAltitude() - prev.getAltitude();
            if (altDiff > 0) totalElevGain += altDiff;
        }
        double elevDiff = (maxAlt > Double.NEGATIVE_INFINITY && minAlt < Double.POSITIVE_INFINITY)
                ? Math.max(0.0, maxAlt - minAlt) : 0.0;

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
        trail.setElevationDiff(Math.round(elevDiff * 10.0) / 10.0);
        trail.setStartLatitude(first.getLatitude());
        trail.setStartLongitude(first.getLongitude());
        trail.setEndLatitude(last.getLatitude());
        trail.setEndLongitude(last.getLongitude());
        // Thumbnail is generated client-side from the trail points, so we no
        // longer pre-bake a Google Static Maps URL here (it was provider-
        // locked and could exceed the column length on long trails).
        trail = trailRepository.save(trail);

        // Save optimized points
        for (TrailPoint tp : optimized) {
            tp.setTrail(trail);
        }
        trailPointRepository.saveAll(optimized);

        // Pre-bake a Google Static Maps PNG so clients (notably iOS users
        // behind restricted networks) don't need to fetch from
        // maps.googleapis.com themselves. On failure the field stays
        // null and the client falls back to the dynamic render.
        String thumbPath = trailThumbnailService.generateAndStore(trail.getId(), optimized);
        if (thumbPath != null) {
            trail.setImageUrl(thumbPath);
            trail = trailRepository.save(trail);
        }

        return TrailDto.fromEntity(trail);
    }

    public List<TrailPoint> getTrailPoints(Long trailId) {
        return trailPointRepository.findByTrailIdOrderBySequenceIndexAsc(trailId);
    }

    /**
     * Visible trails within {@code radiusMeters} of (lat,lng), sorted by exact
     * distance ascending. Uses a bounding-box DB filter then refines in Java.
     * Cap defaults to 50 rows.
     */
    public List<TrailDto> getVisibleNearby(Long userId, double lat, double lng,
                                           double radiusMeters, int limit) {
        // 1 deg latitude ≈ 111_320 m; 1 deg longitude scales by cos(lat).
        double latDelta = radiusMeters / 111_320.0;
        double cosLat = Math.cos(Math.toRadians(lat));
        double lngDelta = cosLat == 0 ? latDelta : radiusMeters / (111_320.0 * cosLat);
        // Pull a generous superset from DB, then refine.
        List<Trail> raw = trailRepository.findVisibleInBoundingBox(
                userId,
                lat - latDelta, lat + latDelta,
                lng - lngDelta, lng + lngDelta,
                Math.max(limit * 4, 100));
        List<Trail> filtered = new ArrayList<>();
        for (Trail t : raw) {
            if (t.getStartLatitude() == null || t.getStartLongitude() == null) continue;
            double d = GeoUtils.haversineKm(lat, lng,
                    t.getStartLatitude(), t.getStartLongitude()) * 1000.0;
            if (d <= radiusMeters) filtered.add(t);
        }
        filtered.sort((a, b) -> Double.compare(
                GeoUtils.haversineKm(lat, lng, a.getStartLatitude(), a.getStartLongitude()),
                GeoUtils.haversineKm(lat, lng, b.getStartLatitude(), b.getStartLongitude())));
        if (filtered.size() > limit) {
            filtered = filtered.subList(0, limit);
        }
        List<Long> creatorIds = filtered.stream()
                .map(Trail::getCreatorId).distinct().collect(Collectors.toList());
        Map<Long, User> creatorMap = userRepository.findAllById(creatorIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));
        return filtered.stream()
                .map(t -> TrailDto.fromEntity(t, creatorMap.get(t.getCreatorId())))
                .toList();
    }

    /**
     * Backfill missing thumbnails for trails whose imageUrl is null/empty.
     * Returns a summary map: total / generated / skipped (no points) / failed.
     */
    public Map<String, Object> backfillMissingThumbnails() {
        List<Trail> all = trailRepository.findAll();
        int total = 0;
        int generated = 0;
        int skipped = 0;
        int failed = 0;
        for (Trail t : all) {
            if (t.isDeleted()) continue;
            String url = t.getImageUrl();
            if (url != null && !url.isBlank()) continue;
            total++;
            List<TrailPoint> pts =
                    trailPointRepository.findByTrailIdOrderBySequenceIndexAsc(t.getId());
            if (pts.isEmpty()) { skipped++; continue; }
            String thumbPath = trailThumbnailService.generateAndStore(t.getId(), pts);
            if (thumbPath == null) { failed++; continue; }
            t.setImageUrl(thumbPath);
            trailRepository.save(t);
            generated++;
        }
        return Map.of(
                "total", total,
                "generated", generated,
                "skipped", skipped,
                "failed", failed
        );
    }
}
