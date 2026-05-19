import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/ebike.dart';

void main() {
  group('EBike.fromJson', () {
    test('parses with module + model data', () {
      final bike = EBike.fromJson({
        'id': 7,
        'name': 'Stinger',
        'traxSerialNumber': 'SN-001',
        'motor': '500W',
        'controller': 'C-X',
        'battery': '48V/20Ah',
        'modelBrand': 'TRAX',
        'modelName': 'Stinger Pro',
        'connected': true,
        'createdAt': '2026-05-18T00:00:00Z',
      });
      expect(bike.id, '7');
      expect(bike.name, 'Stinger');
      expect(bike.traxSerialNumber, 'SN-001');
      expect(bike.motor, '500W');
      expect(bike.modelData, isNotNull);
      expect(bike.modelData!.brand, 'TRAX');
      expect(bike.isConnected, isTrue);
    });

    test('reads isConnected fallback when "connected" missing', () {
      final bike = EBike.fromJson({
        'id': 1,
        'name': 'A',
        'isConnected': true,
      });
      expect(bike.isConnected, isTrue);
    });

    test('defaults certified flags to false and uses now() when no createdAt', () {
      final before = DateTime.now();
      final bike = EBike.fromJson({'id': 1, 'name': 'A'});
      expect(bike.motorCertified, isFalse);
      expect(bike.controllerCertified, isFalse);
      expect(bike.batteryCertified, isFalse);
      expect(bike.modelData, isNull);
      expect(bike.createdAt.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('copyWith updates only requested fields', () {
      final bike = EBike(
        id: '1',
        name: 'A',
        motor: 'mA',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = bike.copyWith(name: 'B', motorCertified: true);
      expect(updated.id, '1');
      expect(updated.name, 'B');
      expect(updated.motor, 'mA');
      expect(updated.motorCertified, isTrue);
      expect(updated.createdAt, bike.createdAt);
    });

    test('toJson surfaces module + model fields', () {
      final bike = EBike(
        id: '1',
        name: 'A',
        motor: 'm',
        controller: 'c',
        battery: 'b',
        traxSerialNumber: 'SN',
        createdAt: DateTime(2026, 1, 1),
      );
      final map = bike.toJson();
      expect(map['name'], 'A');
      expect(map['traxSerialNumber'], 'SN');
      expect(map['motorCertified'], isFalse);
    });
  });
}
