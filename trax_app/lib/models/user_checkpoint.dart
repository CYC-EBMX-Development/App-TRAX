class UserCheckpoint {
  final int id;
  final int trailId;
  final int sequenceIndex;
  final double latitude;
  final double longitude;

  const UserCheckpoint({
    required this.id,
    required this.trailId,
    required this.sequenceIndex,
    required this.latitude,
    required this.longitude,
  });

  factory UserCheckpoint.fromJson(Map<String, dynamic> json) {
    return UserCheckpoint(
      id: (json['id'] as num).toInt(),
      trailId: (json['trailId'] as num?)?.toInt() ?? 0,
      sequenceIndex: (json['sequenceIndex'] as num?)?.toInt() ?? 0,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}
