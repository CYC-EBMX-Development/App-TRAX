import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/ride_lap.dart';

/// Snapshot of the checkpoints used during a recorded ride.
///
/// Returns a map from sequenceIndex to representative LatLng, derived from
/// the stored pass coordinates (each pass record stores the rider's lat/lng
/// at the moment the checkpoint was crossed). Using stored pass coordinates
/// makes records and replays immune to later edits of the trail's user
/// checkpoints.
Map<int, LatLng> rideCheckpointPositions(List<RideLap> laps) {
  final out = <int, LatLng>{};
  for (final lap in laps) {
    for (final pass in lap.checkpointPasses) {
      if (pass.latitude == null || pass.longitude == null) continue;
      // Keep the first (chronologically earliest) recorded position per CP
      // so the marker is stable across multi-lap rides.
      out.putIfAbsent(
          pass.sequenceIndex, () => LatLng(pass.latitude!, pass.longitude!));
    }
  }
  return out;
}
