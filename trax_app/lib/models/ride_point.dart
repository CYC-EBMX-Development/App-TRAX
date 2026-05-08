class RidePoint {
  final double latitude;
  final double longitude;
  final double speed;
  final double altitude;
  final DateTime timestamp;

  RidePoint({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.altitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'altitude': altitude,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RidePoint.fromJson(Map<String, dynamic> json) {
    return RidePoint(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}
