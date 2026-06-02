import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/ride_lap.dart';

void main() {
  group('RideLap', () {
    test('parses lap with checkpoint passes', () {
      final lap = RideLap.fromJson({
        'lapNumber': 2,
        'durationSeconds': 75,
        'distanceKm': 1.2,
        'overlapPercent': 95.5,
        'startTime': '2026-05-18T10:01:00Z',
        'endTime':   '2026-05-18T10:02:15Z',
        'checkpointPasses': [
          {'sequenceIndex': 1, 'secondsFromLapStart': 30, 'latitude': 31.0, 'longitude': 121.0},
        ],
      });
      expect(lap.lapNumber, 2);
      expect(lap.durationSeconds, 75);
      expect(lap.distanceKm, 1.2);
      expect(lap.overlapPercent, 95.5);
      expect(lap.checkpointPasses, hasLength(1));
      expect(lap.checkpointPasses.first.sequenceIndex, 1);
    });

    test('handles missing fields with defaults', () {
      final lap = RideLap.fromJson({});
      expect(lap.lapNumber, 0);
      expect(lap.durationSeconds, 0);
      expect(lap.distanceKm, 0);
      expect(lap.overlapPercent, isNull);
      expect(lap.checkpointPasses, isEmpty);
    });

    test('formatted minute:seconds for < 1 hour', () {
      expect(RideLap(lapNumber: 1, durationSeconds: 65, distanceKm: 1).formatted,
          '1:05');
      expect(RideLap(lapNumber: 1, durationSeconds: 8, distanceKm: 1).formatted,
          '0:08');
    });

    test('formatted h:mm:ss when >= 1 hour', () {
      expect(
          RideLap(lapNumber: 1, durationSeconds: 3725, distanceKm: 1).formatted,
          '1:02:05');
    });

    test('formatLapDuration handles negative input gracefully', () {
      expect(formatLapDuration(-5), '0:00');
    });
  });
}
