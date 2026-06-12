import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'ride_lap.dart';

class RaceLiveData {
  final int raceId;
  final String raceStatus;
  final String gameType;
  final int elapsedSeconds;
  final List<RiderLiveInfo> riders;
  final int? timelineStartMs;
  final int? timelineEndMs;
  final int timelineResolutionMs;
  final List<AlignedFrame> alignedFrames;

  RaceLiveData({
    required this.raceId,
    required this.raceStatus,
    this.gameType = 'RACE',
    required this.elapsedSeconds,
    required this.riders,
    this.timelineStartMs,
    this.timelineEndMs,
    this.timelineResolutionMs = 1000,
    this.alignedFrames = const [],
  });

  factory RaceLiveData.fromJson(Map<String, dynamic> json) {
    return RaceLiveData(
      raceId: (json['raceId'] as num).toInt(),
      raceStatus: json['raceStatus'] ?? 'waiting',
      gameType: (json['gameType'] as String?)?.toUpperCase() ?? 'RACE',
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
        timelineStartMs: (json['timelineStartMs'] as num?)?.toInt(),
        timelineEndMs: (json['timelineEndMs'] as num?)?.toInt(),
        timelineResolutionMs:
          (json['timelineResolutionMs'] as num?)?.toInt() ?? 1000,
        alignedFrames: json['alignedFrames'] != null
          ? (json['alignedFrames'] as List)
            .map((e) => AlignedFrame.fromJson(e as Map<String, dynamic>))
            .toList()
          : const [],
      riders: json['riders'] != null
          ? (json['riders'] as List)
              .map((e) => RiderLiveInfo.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

class RiderLiveInfo {
  final int userId;
  final String? userName;
  final String? userAvatarUrl;
  final int? rideId;
  final String status; // racing, finished, dnf
  final int? finishRank;
  final double latitude;
  final double longitude;
  final double speed;
  final double distanceKm;
  final int durationSeconds;
  final int completedLaps;
  final int? bestLapSeconds;
  final int? lastCapturedAtMs;
  final List<RideLap> laps;
  final List<LatLng> route;
  final int? bicycleId;
  final String? bicycleName;
  final String? bicycleImageUrl;

  RiderLiveInfo({
    required this.userId,
    this.userName,
    this.userAvatarUrl,
    this.rideId,
    required this.status,
    this.finishRank,
    this.latitude = 0,
    this.longitude = 0,
    this.speed = 0,
    this.distanceKm = 0,
    this.durationSeconds = 0,
    this.completedLaps = 0,
    this.bestLapSeconds,
    this.lastCapturedAtMs,
    this.laps = const [],
    this.route = const [],
    this.bicycleId,
    this.bicycleName,
    this.bicycleImageUrl,
  });

  factory RiderLiveInfo.fromJson(Map<String, dynamic> json) {
    return RiderLiveInfo(
      userId: (json['userId'] as num).toInt(),
      userName: json['userName'],
      userAvatarUrl: json['userAvatarUrl'],
      rideId: (json['rideId'] as num?)?.toInt(),
      status: json['status'] ?? 'racing',
      finishRank: (json['finishRank'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      completedLaps: (json['completedLaps'] as num?)?.toInt() ?? 0,
      bestLapSeconds: (json['bestLapSeconds'] as num?)?.toInt(),
        lastCapturedAtMs: (json['lastCapturedAtMs'] as num?)?.toInt(),
      laps: json['laps'] != null
          ? (json['laps'] as List)
              .map((e) => RideLap.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      route: json['route'] != null
          ? (json['route'] as List)
              .map((e) {
                final m = e as Map<String, dynamic>;
                return LatLng(
                  (m['latitude'] as num).toDouble(),
                  (m['longitude'] as num).toDouble(),
                );
              })
              .toList()
          : [],
      bicycleId: (json['bicycleId'] as num?)?.toInt(),
      bicycleName: json['bicycleName'],
      bicycleImageUrl: json['bicycleImageUrl'],
    );
  }
}

class AlignedFrame {
  final int capturedAtMs;
  final List<AlignedRiderPoint> riders;

  AlignedFrame({required this.capturedAtMs, this.riders = const []});

  factory AlignedFrame.fromJson(Map<String, dynamic> json) {
    return AlignedFrame(
      capturedAtMs: (json['capturedAtMs'] as num).toInt(),
      riders: json['riders'] != null
          ? (json['riders'] as List)
              .map((e) => AlignedRiderPoint.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }
}

class AlignedRiderPoint {
  final int userId;
  final double latitude;
  final double longitude;
  final double speed;

  AlignedRiderPoint({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.speed = 0,
  });

  factory AlignedRiderPoint.fromJson(Map<String, dynamic> json) {
    return AlignedRiderPoint(
      userId: (json['userId'] as num).toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
    );
  }
}
