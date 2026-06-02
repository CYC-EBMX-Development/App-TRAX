import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/user.dart';

void main() {
  group('User.fromJson', () {
    test('parses full payload', () {
      final user = User.fromJson({
        'id': 42,
        'email': 'alice@trax.com',
        'name': 'alice',
        'avatarUrl': '/avatars/42.jpg',
      });
      expect(user.id, '42');
      expect(user.email, 'alice@trax.com');
      expect(user.name, 'alice');
      expect(user.avatarUrl, '/avatars/42.jpg');
    });

    test('handles missing optional fields and null email', () {
      final user = User.fromJson({});
      expect(user.id, isNull);
      expect(user.email, '');
      expect(user.name, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('coerces non-string id to string', () {
      expect(User.fromJson({'id': 7, 'email': 'x@x'}).id, '7');
      expect(User.fromJson({'id': '7', 'email': 'x@x'}).id, '7');
    });
  });

  group('User.toJson', () {
    test('serializes round-trip-compatible map', () {
      final user = User(id: '1', email: 'e@e', name: 'n', avatarUrl: '/a.png');
      final map = user.toJson();
      expect(map['id'], '1');
      expect(map['email'], 'e@e');
      expect(map['name'], 'n');
      expect(map['avatarUrl'], '/a.png');
    });
  });

  group('Bicycle.fromJson / toJson', () {
    test('parses and serializes correctly', () {
      final bike = Bicycle.fromJson({
        'id': 9,
        'name': 'Stinger',
        'brand': 'TRAX',
        'batteryInfo': '48V/20Ah',
        'controllerInfo': 'C-X',
        'motorInfo': '500W',
      });
      expect(bike.id, '9');
      expect(bike.name, 'Stinger');
      expect(bike.brand, 'TRAX');

      final map = bike.toJson();
      expect(map['name'], 'Stinger');
      expect(map['motorInfo'], '500W');
    });

    test('defaults empty name when missing', () {
      final bike = Bicycle.fromJson({});
      expect(bike.name, '');
    });
  });
}
