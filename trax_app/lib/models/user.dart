class User {
  final String? id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final List<Bicycle>? bicycles;

  User({
    this.id,
    required this.email,
    this.name,
    this.avatarUrl,
    this.bicycles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString(),
      email: json['email'] ?? '',
      name: json['name'],
      avatarUrl: json['avatarUrl'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatarUrl': avatarUrl,
      };
}

class Bicycle {
  final String? id;
  final String name;
  final String? brand;
  final String? batteryInfo;
  final String? controllerInfo;
  final String? motorInfo;

  Bicycle({
    this.id,
    required this.name,
    this.brand,
    this.batteryInfo,
    this.controllerInfo,
    this.motorInfo,
  });

  factory Bicycle.fromJson(Map<String, dynamic> json) {
    return Bicycle(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      brand: json['brand'],
      batteryInfo: json['batteryInfo'],
      controllerInfo: json['controllerInfo'],
      motorInfo: json['motorInfo'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'batteryInfo': batteryInfo,
        'controllerInfo': controllerInfo,
        'motorInfo': motorInfo,
      };
}
