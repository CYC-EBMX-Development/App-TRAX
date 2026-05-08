class BikeBrand {
  final int id;
  final String name;
  final String? imageUrl;

  BikeBrand({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  factory BikeBrand.fromJson(Map<String, dynamic> json) {
    return BikeBrand(
      id: json['id'] as int,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
    };
  }
}
