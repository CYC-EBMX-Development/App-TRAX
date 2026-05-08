class ModuleTelemetry {
  final String serialNo;
  final double latitude;
  final double longitude;
  final double speed;
  final int batteryPercent;
  final int signalStrength;
  final String? timestamp;

  ModuleTelemetry({
    required this.serialNo,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.batteryPercent,
    required this.signalStrength,
    this.timestamp,
  });

  factory ModuleTelemetry.fromJson(Map<String, dynamic> json) {
    return ModuleTelemetry(
      serialNo: json['serialNo'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      batteryPercent: json['batteryPercent'] as int? ?? 0,
      signalStrength: json['signalStrength'] as int? ?? 0,
      timestamp: json['timestamp'] as String?,
    );
  }
}
