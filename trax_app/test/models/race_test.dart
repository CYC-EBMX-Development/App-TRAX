import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/models/race.dart';

void main() {
  group('Race.fromJson', () {
    test('parses full race payload', () {
      final race = Race.fromJson({
        'id': 7,
        'name': 'Friday Night Race',
        'hostId': 1,
        'hostName': 'alice',
        'trailId': 100,
        'trailName': 'Bay Loop',
        'trailDistance': 5.5,
        'maxParticipants': 8,
        'currentParticipants': 3,
        'targetLaps': 5,
        'isPublic': true,
        'joinCode': 'ABCD12',
        'status': 'in_progress',
        'gameType': 'laps',
        'startedAt': '2026-05-18T18:00:00Z',
        'participants': [
          {'id': 1, 'userId': 1, 'role': 'host', 'status': 'racing'},
          {'id': 2, 'userId': 2, 'role': 'rider', 'status': 'joined'},
        ],
        'myRole': 'host',
      });
      expect(race.id, 7);
      expect(race.name, 'Friday Night Race');
      expect(race.trailDistance, 5.5);
      expect(race.gameType, 'LAPS');
      expect(race.isLaps, isTrue);
      expect(race.isInProgress, isTrue);
      expect(race.isHost, isTrue);
      expect(race.participants, hasLength(2));
    });

    test('applies defaults on minimal payload', () {
      final race = Race.fromJson({'id': 1});
      expect(race.name, '');
      expect(race.maxParticipants, 10);
      expect(race.targetLaps, 1);
      expect(race.status, 'waiting');
      expect(race.gameType, 'RACE');
      expect(race.isWaiting, isTrue);
      expect(race.isHost, isFalse);
    });

    test('reads "public" alias when "isPublic" missing', () {
      final r1 = Race.fromJson({'id': 1, 'public': false});
      expect(r1.isPublic, isFalse);

      final r2 = Race.fromJson({'id': 1, 'isPublic': false, 'public': true});
      // 'public' is read first and wins when both are present
      expect(r2.isPublic, isTrue);
    });

    test('copyWith only overrides given fields', () {
      final r = Race.fromJson({'id': 1, 'isPublic': true, 'status': 'waiting'});
      final r2 = r.copyWith(status: 'in_progress');
      expect(r2.status, 'in_progress');
      expect(r2.isPublic, isTrue);
      expect(r2.id, r.id);
    });
  });

  group('RaceParticipant.fromJson', () {
    test('parses with all fields', () {
      final p = RaceParticipant.fromJson({
        'id': 1,
        'userId': 5,
        'userName': 'bob',
        'role': 'rider',
        'status': 'finished',
        'finishRank': 2,
        'bicycleId': 9,
        'bicycleName': 'Stinger',
      });
      expect(p.userId, 5);
      expect(p.role, 'rider');
      expect(p.isFinished, isTrue);
      expect(p.isRider, isTrue);
      expect(p.isHost, isFalse);
      expect(p.finishRank, 2);
    });

    test('host role is also a rider', () {
      final p = RaceParticipant.fromJson({
        'id': 1, 'userId': 1, 'role': 'host', 'status': 'racing',
      });
      expect(p.isHost, isTrue);
      expect(p.isRider, isTrue);
      expect(p.isObserver, isFalse);
    });

    test('defaults role and status', () {
      final p = RaceParticipant.fromJson({'id': 1, 'userId': 5});
      expect(p.role, 'rider');
      expect(p.status, 'joined');
    });
  });
}
