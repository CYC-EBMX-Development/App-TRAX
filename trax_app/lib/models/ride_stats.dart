import 'ride_lap.dart';

class RideStats {
  final int rideId;
  final String status;
  final int durationSeconds;
  final double distanceKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double elevationMeters;
  final double currentLatitude;
  final double currentLongitude;
  final int? targetLaps;
  final int? completedLaps;
  final List<RideLap> laps;

  RideStats({
    required this.rideId,
    required this.status,
    required this.durationSeconds,
    required this.distanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.elevationMeters,
    required this.currentLatitude,
    required this.currentLongitude,
    this.targetLaps,
    this.completedLaps,
    this.laps = const [],
  });

  factory RideStats.fromJson(Map<String, dynamic> json) {
    return RideStats(
      rideId: json['rideId'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      avgSpeedKmh: (json['avgSpeedKmh'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (json['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
      elevationMeters: (json['elevationMeters'] as num?)?.toDouble() ?? 0,
      currentLatitude: (json['currentLatitude'] as num?)?.toDouble() ?? 0,
      currentLongitude: (json['currentLongitude'] as num?)?.toDouble() ?? 0,
      targetLaps: (json['targetLaps'] as num?)?.toInt(),
      completedLaps: (json['completedLaps'] as num?)?.toInt(),
      laps: (json['laps'] as List?)
              ?.map((e) => RideLap.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
