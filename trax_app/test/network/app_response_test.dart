import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/common/network/app_response.dart';

void main() {
  group('AppResponse', () {
    test('fromJson success path', () {
      final r = AppResponse.fromJson({
        'flag': true,
        'code': 200,
        'message': 'ok',
        'data': {'x': 1},
      });
      expect(r.isSuccess(), isTrue);
      expect(r.code, 200);
      expect(r.message, 'ok');
      expect((r.data as Map)['x'], 1);
    });

    test('fromJson defaults flag to true when missing', () {
      final r = AppResponse.fromJson({'code': 200, 'message': 'm'});
      expect(r.isSuccess(), isTrue);
    });

    test('fromJson failure path', () {
      final r = AppResponse.fromJson({
        'flag': false,
        'code': 40000,
        'message': 'Bad creds',
      });
      expect(r.isSuccess(), isFalse);
      expect(r.code, 40000);
      expect(r.data, isNull);
    });

    test('AppResponse.error constructor', () {
      final r = AppResponse.error('Network down');
      expect(r.isSuccess(), isFalse);
      expect(r.code, -1);
      expect(r.message, 'Network down');
      expect(r.data, isNull);
    });
  });
}
