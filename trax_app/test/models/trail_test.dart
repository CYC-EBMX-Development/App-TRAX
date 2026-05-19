import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/trail.dart';

void main() {
  group('Trail.fromJson', () {
    test('parses with all fields', () {
      final t = Trail.fromJson({
        'id': 12,
        'name': 'Bay Loop',
        'location': 'Shanghai',
        'difficulty': 'hard',
        'public': false,
        'description': 'fast',
        'imageUrl': '/t.jpg',
        'distance': 5.5,
        'elevation': 200.0,
        'elevationDiff': 100.0,
        'type': 'lap',
        'creatorId': 1,
        'creatorName': 'alice',
        'startLatitude': 31.0,
        'startLongitude': 121.0,
        'endLatitude': 31.001,
        'endLongitude': 121.001,
        'createdAt': '2026-05-18T00:00:00Z',
      });
      expect(t.id, '12');
      expect(t.name, 'Bay Loop');
      expect(t.difficulty, 'hard');
      expect(t.isPublic, isFalse);
      expect(t.distance, 5.5);
      expect(t.type, 'lap');
      expect(t.createdAt, isNotNull);
    });

    test('applies defaults on minimal payload', () {
      final t = Trail.fromJson({});
      expect(t.id, isNull);
      expect(t.name, '');
      expect(t.difficulty, 'medium');
      expect(t.isPublic, isTrue);
      expect(t.distance, isNull);
      expect(t.createdAt, isNull);
    });

    test('toJson includes all expected keys', () {
      final t = Trail(name: 'X', difficulty: 'easy', distance: 1.0);
      final map = t.toJson();
      expect(map['name'], 'X');
      expect(map['difficulty'], 'easy');
      expect(map['distance'], 1.0);
      expect(map['isPublic'], isTrue);
    });
  });
}
