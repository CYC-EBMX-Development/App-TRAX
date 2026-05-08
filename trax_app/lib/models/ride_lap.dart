class RideLap {
  final int lapNumber;
  final int durationSeconds;
  final double distanceKm;
  final double? overlapPercent;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<LapCheckpointPass> checkpointPasses;

  RideLap({
    required this.lapNumber,
    required this.durationSeconds,
    required this.distanceKm,
    this.overlapPercent,
    this.startTime,
    this.endTime,
    this.checkpointPasses = const [],
  });

  factory RideLap.fromJson(Map<String, dynamic> json) {
    final passesRaw = json['checkpointPasses'];
    final passes = (passesRaw is List)
        ? passesRaw
            .map((e) =>
                LapCheckpointPass.fromJson(e as Map<String, dynamic>))
            .toList()
        : <LapCheckpointPass>[];
    return RideLap(
      lapNumber: (json['lapNumber'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      overlapPercent: (json['overlapPercent'] as num?)?.toDouble(),
      startTime: json['startTime'] != null
          ? DateTime.tryParse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'] as String)
          : null,
      checkpointPasses: passes,
    );
  }

  /// "1:23.4" / "12:05" / "1:02:34" formatting
  String get formatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final mm = (m % 60).toString().padLeft(2, '0');
      final ss = s.toString().padLeft(2, '0');
      return '$h:$mm:$ss';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class LapCheckpointPass {
  final int sequenceIndex;
  final DateTime? passTime;
  final int secondsFromLapStart;
  final double? latitude;
  final double? longitude;

  const LapCheckpointPass({
    required this.sequenceIndex,
    required this.passTime,
    required this.secondsFromLapStart,
    this.latitude,
    this.longitude,
  });

  factory LapCheckpointPass.fromJson(Map<String, dynamic> json) {
    return LapCheckpointPass(
      sequenceIndex: (json['sequenceIndex'] as num?)?.toInt() ?? 0,
      passTime: json['passTime'] != null
          ? DateTime.tryParse(json['passTime'] as String)
          : null,
      secondsFromLapStart:
          (json['secondsFromLapStart'] as num?)?.toInt() ?? 0,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// "M:SS" formatter shared by lap split UIs.
String formatLapDuration(int seconds) {
  if (seconds < 0) seconds = 0;
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m >= 60) {
    final h = m ~/ 60;
    final mm = (m % 60).toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$h:$mm:$ss';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
