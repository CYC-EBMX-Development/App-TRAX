class Trail {
  final String? id;
  final String name;
  final String? location;
  final String difficulty; // easy, medium, hard, extreme
  final bool isPublic;
  final String? description;
  final String? imageUrl;
  final double? distance; // km
  final double? elevation; // meters (cumulative gain)
  final double? elevationDiff; // meters (max altitude - min altitude)
  final String? type; // free_ride, lap
  final int? creatorId;
  final String? creatorName;
  final String? creatorAvatarUrl;
  final double? startLatitude;
  final double? startLongitude;
  final double? endLatitude;
  final double? endLongitude;
  final DateTime? createdAt;

  Trail({
    this.id,
    required this.name,
    this.location,
    this.difficulty = 'medium',
    this.isPublic = true,
    this.description,
    this.imageUrl,
    this.distance,
    this.elevation,
    this.elevationDiff,
    this.type,
    this.creatorId,
    this.creatorName,
    this.creatorAvatarUrl,
    this.startLatitude,
    this.startLongitude,
    this.endLatitude,
    this.endLongitude,
    this.createdAt,
  });

  factory Trail.fromJson(Map<String, dynamic> json) {
    return Trail(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      location: json['location'],
      difficulty: json['difficulty'] ?? 'medium',
      isPublic: json['public'] ?? true,
      description: json['description'],
      imageUrl: json['imageUrl'],
      distance: (json['distance'] as num?)?.toDouble(),
      elevation: (json['elevation'] as num?)?.toDouble(),
      elevationDiff: (json['elevationDiff'] as num?)?.toDouble(),
      type: json['type'],
      creatorId: (json['creatorId'] as num?)?.toInt(),
      creatorName: json['creatorName'],
      creatorAvatarUrl: json['creatorAvatarUrl'],
      startLatitude: (json['startLatitude'] as num?)?.toDouble(),
      startLongitude: (json['startLongitude'] as num?)?.toDouble(),
      endLatitude: (json['endLatitude'] as num?)?.toDouble(),
      endLongitude: (json['endLongitude'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'difficulty': difficulty,
        'isPublic': isPublic,
        'description': description,
        'imageUrl': imageUrl,
        'distance': distance,
        'elevation': elevation,
        'elevationDiff': elevationDiff,
        'type': type,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'creatorAvatarUrl': creatorAvatarUrl,
        'startLatitude': startLatitude,
        'startLongitude': startLongitude,
        'endLatitude': endLatitude,
        'endLongitude': endLongitude,
        'createdAt': createdAt?.toIso8601String(),
      };
}
