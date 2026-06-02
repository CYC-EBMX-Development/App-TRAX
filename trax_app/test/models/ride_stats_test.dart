import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/ride_stats.dart';

void main() {
  group('RideStats.fromJson', () {
    test('parses full payload with laps', () {
      final stats = RideStats.fromJson({
        'rideId': 1,
        'status': 'active',
        'durationSeconds': 120,
        'distanceKm': 2.5,
        'avgSpeedKmh': 18.5,
        'maxSpeedKmh': 25.0,
        'elevationMeters': 12.3,
        'currentLatitude': 31.0,
        'currentLongitude': 121.0,
        'targetLaps': 3,
        'completedLaps': 1,
        'laps': [
          {'lapNumber': 1, 'durationSeconds': 60, 'distanceKm': 1.0},
        ],
      });
      expect(stats.rideId, 1);
      expect(stats.status, 'active');
      expect(stats.durationSeconds, 120);
      expect(stats.distanceKm, 2.5);
      expect(stats.targetLaps, 3);
      expect(stats.completedLaps, 1);
      expect(stats.laps, hasLength(1));
    });

    test('defaults zero on missing fields', () {
      final stats = RideStats.fromJson({});
      expect(stats.rideId, 0);
      expect(stats.status, '');
      expect(stats.durationSeconds, 0);
      expect(stats.distanceKm, 0);
      expect(stats.laps, isEmpty);
      expect(stats.targetLaps, isNull);
      expect(stats.completedLaps, isNull);
    });

    test('handles laps:null gracefully', () {
      final stats = RideStats.fromJson({'rideId': 1, 'laps': null});
      expect(stats.laps, isEmpty);
    });
  });
}
