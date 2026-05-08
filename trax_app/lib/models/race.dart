class Race {
  final int id;
  final String name;
  final int hostId;
  final String? hostName;
  final String? hostAvatarUrl;
  final int? trailId;
  final String? trailName;
  final double? trailDistance;
  final DateTime? scheduledTime;
  final int maxParticipants;
  final int currentParticipants;
  final int targetLaps;
  final bool isPublic;
  final String? notes;
  final String joinCode;
  final String status; // waiting, in_progress, completed, canceled
  final String gameType; // RACE | LAPS
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;
  final List<RaceParticipant> participants;
  final String? myRole; // host, rider, observer, null

  Race({
    required this.id,
    required this.name,
    required this.hostId,
    this.hostName,
    this.hostAvatarUrl,
    this.trailId,
    this.trailName,
    this.trailDistance,
    this.scheduledTime,
    this.maxParticipants = 10,
    this.currentParticipants = 0,
    this.targetLaps = 1,
    this.isPublic = true,
    this.notes,
    this.joinCode = '',
    this.status = 'waiting',
    this.gameType = 'RACE',
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.participants = const [],
    this.myRole,
  });

  factory Race.fromJson(Map<String, dynamic> json) {
    return Race(
      id: (json['id'] as num).toInt(),
      name: json['name'] ?? '',
      hostId: (json['hostId'] as num?)?.toInt() ?? 0,
      hostName: json['hostName'],
      hostAvatarUrl: json['hostAvatarUrl'],
      trailId: (json['trailId'] as num?)?.toInt(),
      trailName: json['trailName'],
      trailDistance: (json['trailDistance'] as num?)?.toDouble(),
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.tryParse(json['scheduledTime'])
          : null,
      maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 10,
      currentParticipants: (json['currentParticipants'] as num?)?.toInt() ?? 0,
      targetLaps: (json['targetLaps'] as num?)?.toInt() ?? 1,
      isPublic: json['public'] ?? json['isPublic'] ?? true,
      notes: json['notes'],
      joinCode: json['joinCode'] ?? '',
      status: json['status'] ?? 'waiting',
      gameType: (json['gameType'] as String?)?.toUpperCase() ?? 'RACE',
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'])
          : null,
      endedAt: json['endedAt'] != null
          ? DateTime.tryParse(json['endedAt'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      participants: json['participants'] != null
          ? (json['participants'] as List)
              .map((e) => RaceParticipant.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      myRole: json['myRole'],
    );
  }

  bool get isWaiting => status == 'waiting';
  bool get isPreparing => status == 'preparing';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isCanceled => status == 'canceled';
  bool get isLaps => gameType == 'LAPS';
  bool get isHost => myRole == 'host';
  bool get isRider => myRole == 'rider';
  bool get isObserver => myRole == 'observer';

  Race copyWith({bool? isPublic, String? status}) {
    return Race(
      id: id, name: name, hostId: hostId, hostName: hostName,
      hostAvatarUrl: hostAvatarUrl, trailId: trailId, trailName: trailName,
      trailDistance: trailDistance, scheduledTime: scheduledTime,
      maxParticipants: maxParticipants, currentParticipants: currentParticipants,
      targetLaps: targetLaps, isPublic: isPublic ?? this.isPublic,
      notes: notes, joinCode: joinCode, status: status ?? this.status,
      gameType: gameType,
      startedAt: startedAt, endedAt: endedAt, createdAt: createdAt,
      participants: participants, myRole: myRole,
    );
  }
}

class RaceParticipant {
  final int id;
  final int userId;
  final String? userName;
  final String? userAvatarUrl;
  final String role;     // host, rider, observer
  final String status;   // joined, racing, finished, dnf
  final int? rideId;
  final int? finishRank;
  final DateTime? joinedAt;
  final int? bicycleId;
  final String? bicycleName;
  final String? bicycleImageUrl;
  final String? bicycleBrand;
  final String? bicycleModel;
  final String? bicycleMotor;
  final String? bicycleBattery;

  RaceParticipant({
    required this.id,
    required this.userId,
    this.userName,
    this.userAvatarUrl,
    required this.role,
    required this.status,
    this.rideId,
    this.finishRank,
    this.joinedAt,
    this.bicycleId,
    this.bicycleName,
    this.bicycleImageUrl,
    this.bicycleBrand,
    this.bicycleModel,
    this.bicycleMotor,
    this.bicycleBattery,
  });

  factory RaceParticipant.fromJson(Map<String, dynamic> json) {
    return RaceParticipant(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      userName: json['userName'],
      userAvatarUrl: json['userAvatarUrl'],
      role: json['role'] ?? 'rider',
      status: json['status'] ?? 'joined',
      rideId: (json['rideId'] as num?)?.toInt(),
      finishRank: (json['finishRank'] as num?)?.toInt(),
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'])
          : null,
      bicycleId: (json['bicycleId'] as num?)?.toInt(),
      bicycleName: json['bicycleName'],
      bicycleImageUrl: json['bicycleImageUrl'],
      bicycleBrand: json['bicycleBrand'],
      bicycleModel: json['bicycleModel'],
      bicycleMotor: json['bicycleMotor'],
      bicycleBattery: json['bicycleBattery'],
    );
  }

  bool get isHost => role == 'host';
  bool get isRider => role == 'rider' || role == 'host';
  bool get isObserver => role == 'observer';
  bool get isReady => status == 'ready';
  bool get isFinished => status == 'finished';
  bool get isDnf => status == 'dnf';
}
