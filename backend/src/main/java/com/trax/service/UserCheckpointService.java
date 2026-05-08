package com.trax.service;

import com.trax.dto.UserCheckpointDto;
import com.trax.model.Trail;
import com.trax.model.TrailPoint;
import com.trax.model.User;
import com.trax.model.UserCheckpoint;
import com.trax.repository.TrailPointRepository;
import com.trax.repository.TrailRepository;
import com.trax.repository.UserCheckpointRepository;
import com.trax.repository.UserRepository;
import com.trax.util.GeoUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
public class UserCheckpointService {
    /** Maximum allowed perpendicular distance from trail polyline for a
     *  checkpoint to be considered "on the trail" (10 m). */
    public static final double PLACEMENT_TOLERANCE_M = 10.0;

    /** Maximum number of checkpoints a user can place on a single trail. */
    public static final int MAX_CHECKPOINTS = 4;

    private final UserCheckpointRepository checkpointRepo;
    private final TrailRepository trailRepo;
    private final TrailPointRepository trailPointRepo;
    private final UserRepository userRepo;

    public UserCheckpointService(UserCheckpointRepository checkpointRepo,
                                 TrailRepository trailRepo,
                                 TrailPointRepository trailPointRepo,
                                 UserRepository userRepo) {
        this.checkpointRepo = checkpointRepo;
        this.trailRepo = trailRepo;
        this.trailPointRepo = trailPointRepo;
        this.userRepo = userRepo;
    }

    public List<UserCheckpointDto> list(Long userId, Long trailId) {
        return checkpointRepo
                .findByUserIdAndTrailIdOrderBySequenceIndexAsc(userId, trailId)
                .stream()
                .map(UserCheckpointDto::fromEntity)
                .toList();
    }

    @Transactional
    public List<UserCheckpointDto> add(Long userId, Long trailId, double lat, double lng) {
        Trail trail = trailRepo.findById(trailId)
                .orElseThrow(() -> new IllegalArgumentException("Trail not found"));

        List<double[]> polyline = loadTrailPolyline(trailId);
        if (polyline.size() < 2) {
            throw new IllegalArgumentException("Trail has no path");
        }

        double distM = GeoUtils.pointToPolylineMeters(lat, lng, polyline);
        if (distM > PLACEMENT_TOLERANCE_M) {
            throw new IllegalArgumentException("Checkpoint is not on the trail");
        }

        long count = checkpointRepo.countByUserIdAndTrailId(userId, trailId);
        if (count >= MAX_CHECKPOINTS) {
            throw new IllegalArgumentException("Max " + MAX_CHECKPOINTS + " checkpoints");
        }

        User user = userRepo.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found"));

        UserCheckpoint cp = new UserCheckpoint();
        cp.setUser(user);
        cp.setTrail(trail);
        cp.setLatitude(lat);
        cp.setLongitude(lng);
        // Temporary placeholder; final value assigned by renumber().
        cp.setSequenceIndex((int) (count + 1) + MAX_CHECKPOINTS);
        checkpointRepo.save(cp);

        renumber(userId, trailId, polyline);
        return list(userId, trailId);
    }

    @Transactional
    public List<UserCheckpointDto> delete(Long userId, Long checkpointId) {
        UserCheckpoint cp = checkpointRepo.findByIdAndUserId(checkpointId, userId)
                .orElseThrow(() -> new IllegalArgumentException("Checkpoint not found"));
        Long trailId = cp.getTrail() != null ? cp.getTrail().getId() : null;
        // Soft delete — keep the row so historical ride records that
        // reference the same trail still have referential context.
        cp.setDeletedAt(java.time.LocalDateTime.now());
        checkpointRepo.save(cp);
        if (trailId != null) {
            renumber(userId, trailId, loadTrailPolyline(trailId));
        }
        return trailId != null ? list(userId, trailId) : List.of();
    }

    private List<double[]> loadTrailPolyline(Long trailId) {
        List<TrailPoint> pts = trailPointRepo
                .findByTrailIdOrderBySequenceIndexAsc(trailId);
        List<double[]> out = new ArrayList<>(pts.size());
        for (TrailPoint p : pts) {
            out.add(new double[]{p.getLatitude(), p.getLongitude()});
        }
        return out;
    }

    /**
     * Re-sort all checkpoints for (user, trail) by their position along the
     * trail polyline and persist sequenceIndex 1..N. Two-pass save to dodge
     * the unique constraint on (user, trail, seq).
     */
    private void renumber(Long userId, Long trailId, List<double[]> polyline) {
        List<UserCheckpoint> all = checkpointRepo
                .findByUserIdAndTrailIdOrderBySequenceIndexAsc(userId, trailId);
        if (all.isEmpty()) return;

        if (polyline == null || polyline.size() < 2) {
            // No polyline to project against — fall back to creation order.
            for (int i = 0; i < all.size(); i++) {
                all.get(i).setSequenceIndex(i + 1);
            }
            checkpointRepo.saveAll(all);
            return;
        }

        // Sort by (segmentIndex, segmentFraction) along the trail.
        all.sort(Comparator.comparingDouble(cp -> {
            GeoUtils.Projection pr = GeoUtils.projectOntoPolyline(
                    cp.getLatitude(), cp.getLongitude(), polyline);
            if (pr == null) return Double.MAX_VALUE;
            return pr.segmentIndex + pr.segmentFraction;
        }));

        // Pass 1: park into a high range to avoid colliding with existing
        // sequence indices during the pass-2 update.
        for (int i = 0; i < all.size(); i++) {
            all.get(i).setSequenceIndex(1000 + i);
        }
        checkpointRepo.saveAll(all);

        // Pass 2: assign final 1..N.
        for (int i = 0; i < all.size(); i++) {
            all.get(i).setSequenceIndex(i + 1);
        }
        checkpointRepo.saveAll(all);
    }
}
