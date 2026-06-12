class ModuleTelemetry {
  final String serialNo;
  final double latitude;
  final double longitude;
  /// Altitude in meters above MSL as reported by the module GNSS chip.
  /// `null` when the frame did not include altitude (older firmware).
  final double? altitude;
  final double speed;
  final int batteryPercent;
  final int signalStrength;
  /// Number of GNSS satellites currently used for the fix (SV count).
  /// `null` when the module did not report it.
  final int? satellites;
  final String? timestamp;

  ModuleTelemetry({
    required this.serialNo,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.batteryPercent,
    required this.signalStrength,
    this.altitude,
    this.satellites,
    this.timestamp,
  });

  factory ModuleTelemetry.fromJson(Map<String, dynamic> json) {
    return ModuleTelemetry(
      serialNo: json['serialNo'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      batteryPercent: json['batteryPercent'] as int? ?? 0,
      signalStrength: json['signalStrength'] as int? ?? 0,
      satellites: (json['satellites'] as num?)?.toInt(),
      timestamp: json['timestamp'] as String?,
    );
  }
}
