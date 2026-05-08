class RideRecord {
  final String? id;
  final String? trailId;
  final String? trailName;
  final String? bicycleId;
  final String? bicycleName;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? distance; // km
  final double? avgSpeed; // km/h
  final double? maxSpeed;
  final double? elevation;
  final String? weather;
  final String? status; // active, paused, completed
  final String? mode; // with_module, without_module
  final int? durationSeconds; // actual ride duration excluding pauses
  final int? targetLaps;
  final int? completedLaps;
  final int? raceId;
  final String? source; // free_ride, lap_timer, race
  final String? gameType; // RACE | LAPS (only for race)

  RideRecord({
    this.id,
    this.trailId,
    this.trailName,
    this.bicycleId,
    this.bicycleName,
    this.startTime,
    this.endTime,
    this.distance,
    this.avgSpeed,
    this.maxSpeed,
    this.elevation,
    this.weather,
    this.status,
    this.mode,
    this.durationSeconds,
    this.targetLaps,
    this.completedLaps,
    this.raceId,
    this.source,
    this.gameType,
  });

  Duration? get duration {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!);
    }
    return null;
  }

  factory RideRecord.fromJson(Map<String, dynamic> json) {
    return RideRecord(
      id: json['id']?.toString(),
      trailId: json['trailId']?.toString(),
      trailName: json['trailName'],
      bicycleId: json['bicycleId']?.toString(),
      bicycleName: json['bicycleName'],
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'])
          : null,
      endTime:
          json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      distance: (json['distance'] as num?)?.toDouble(),
      avgSpeed: (json['avgSpeed'] as num?)?.toDouble(),
      maxSpeed: (json['maxSpeed'] as num?)?.toDouble(),
      elevation: (json['elevation'] as num?)?.toDouble(),
      weather: json['weather'],
      status: json['status'],
      mode: json['mode'],
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      targetLaps: (json['targetLaps'] as num?)?.toInt(),
      completedLaps: (json['completedLaps'] as num?)?.toInt(),
      raceId: (json['raceId'] as num?)?.toInt(),
      source: json['source'],
      gameType: json['gameType'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trailId': trailId,
        'trailName': trailName,
        'bicycleId': bicycleId,
        'bicycleName': bicycleName,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'distance': distance,
        'avgSpeed': avgSpeed,
        'maxSpeed': maxSpeed,
        'elevation': elevation,
        'weather': weather,
        'status': status,
        'mode': mode,
        'durationSeconds': durationSeconds,
        'raceId': raceId,
      };
}
