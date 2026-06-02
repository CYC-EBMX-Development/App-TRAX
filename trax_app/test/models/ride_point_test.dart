import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/ride_point.dart';

void main() {
  group('RidePoint', () {
    test('round-trips through toJson/fromJson', () {
      final ts = DateTime.utc(2026, 5, 18, 12, 0, 0);
      final p = RidePoint(
        latitude: 31.23,
        longitude: 121.47,
        speed: 25.5,
        altitude: 8.0,
        timestamp: ts,
      );

      final map = p.toJson();
      expect(map['latitude'], 31.23);
      expect(map['speed'], 25.5);
      expect(map['timestamp'], ts.toIso8601String());

      final p2 = RidePoint.fromJson(map);
      expect(p2.latitude, p.latitude);
      expect(p2.longitude, p.longitude);
      expect(p2.speed, p.speed);
      expect(p2.altitude, p.altitude);
      expect(p2.timestamp.toUtc(), ts);
    });

    test('handles missing fields with zero defaults', () {
      final p = RidePoint.fromJson({});
      expect(p.latitude, 0);
      expect(p.longitude, 0);
      expect(p.speed, 0);
      expect(p.altitude, 0);
      // timestamp falls back to DateTime.now() — just ensure it parsed
      expect(p.timestamp, isA<DateTime>());
    });

    test('coerces int to double', () {
      final p = RidePoint.fromJson({
        'latitude': 1,
        'longitude': 2,
        'speed': 3,
        'altitude': 4,
      });
      expect(p.latitude, 1.0);
      expect(p.speed, 3.0);
    });
  });
}
