enum HistoryType { added, upgraded }

class EBikeHistory {
  final String id;
  final String bikeId;
  final DateTime timestamp;
  final HistoryType type;
  final Map<String, String> changes;

  const EBikeHistory({
    required this.id,
    required this.bikeId,
    required this.timestamp,
    required this.type,
    required this.changes,
  });

  String get summary {
    if (type == HistoryType.added) return 'Bike added to garage';
    if (changes.isEmpty) return 'Bike updated';
    return 'Updated: ${changes.keys.join(', ')}';
  }
}
