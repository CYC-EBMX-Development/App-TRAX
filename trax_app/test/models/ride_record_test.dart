import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/ride_record.dart';

void main() {
  group('RideRecord.fromJson', () {
    test('parses full ride payload', () {
      final rec = RideRecord.fromJson({
        'id': 7,
        'trailId': 100,
        'trailName': 'Bay',
        'bicycleId': 9,
        'bicycleName': 'Stinger',
        'startTime': '2026-05-18T10:00:00Z',
        'endTime':   '2026-05-18T10:30:00Z',
        'distance': 10.5,
        'avgSpeed': 21.0,
        'maxSpeed': 35.0,
        'elevation': 80.5,
        'status': 'completed',
        'mode': 'with_module',
        'durationSeconds': 1800,
        'targetLaps': 3,
        'completedLaps': 3,
        'raceId': 1,
        'source': 'race',
        'gameType': 'LAPS',
      });
      expect(rec.id, '7');
      expect(rec.trailId, '100');
      expect(rec.bicycleId, '9');
      expect(rec.distance, 10.5);
      expect(rec.durationSeconds, 1800);
      expect(rec.source, 'race');
      expect(rec.gameType, 'LAPS');
    });

    test('duration getter computes correctly when both timestamps present', () {
      final rec = RideRecord(
        startTime: DateTime.utc(2026, 5, 18, 10, 0, 0),
        endTime: DateTime.utc(2026, 5, 18, 10, 5, 0),
      );
      expect(rec.duration, const Duration(minutes: 5));
    });

    test('duration getter returns null when timestamps missing', () {
      expect(RideRecord().duration, isNull);
      expect(RideRecord(startTime: DateTime.now()).duration, isNull);
    });

    test('toJson omits derived fields that are not part of the contract', () {
      final rec = RideRecord(id: '1', distance: 2.0, status: 'completed');
      final map = rec.toJson();
      expect(map['id'], '1');
      expect(map['distance'], 2.0);
      expect(map['status'], 'completed');
    });
  });
}
