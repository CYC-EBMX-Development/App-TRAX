import 'ebike_model_data.dart';

class EBike {
  final String id;
  final String name;
  final String? imageUrl;
  final String? traxSerialNumber;
  final String motor;
  final String controller;
  final String battery;
  final bool motorCertified;
  final bool controllerCertified;
  final bool batteryCertified;
  final EBikeModelData? modelData;
  final EBikeType? type;
  final String? other;
  final bool isConnected;
  final DateTime createdAt;

  const EBike({
    required this.id,
    required this.name,
    this.imageUrl,
    this.traxSerialNumber,
    this.motor = '',
    this.controller = '',
    this.battery = '',
    this.motorCertified = false,
    this.controllerCertified = false,
    this.batteryCertified = false,
    this.modelData,
    this.type,
    this.other,
    this.isConnected = false,
    required this.createdAt,
  });

  EBike copyWith({
    String? name,
    String? imageUrl,
    String? traxSerialNumber,
    String? motor,
    String? controller,
    String? battery,
    bool? motorCertified,
    bool? controllerCertified,
    bool? batteryCertified,
    EBikeModelData? modelData,
    EBikeType? type,
    String? other,
    bool? isConnected,
  }) {
    return EBike(
      id: id,
      createdAt: createdAt,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      traxSerialNumber: traxSerialNumber ?? this.traxSerialNumber,
      motor: motor ?? this.motor,
      controller: controller ?? this.controller,
      battery: battery ?? this.battery,
      motorCertified: motorCertified ?? this.motorCertified,
      controllerCertified: controllerCertified ?? this.controllerCertified,
      batteryCertified: batteryCertified ?? this.batteryCertified,
      modelData: modelData ?? this.modelData,
      type: type ?? this.type,
      other: other ?? this.other,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'imageUrl': imageUrl,
      'motor': motor,
      'controller': controller,
      'battery': battery,
      'motorCertified': motorCertified,
      'controllerCertified': controllerCertified,
      'batteryCertified': batteryCertified,
      'other': other,
      'traxSerialNumber': traxSerialNumber,
      'modelBrand': modelData?.brand,
      'modelName': modelData?.model,
    };
  }

  static EBike fromJson(Map<String, dynamic> json) {
    EBikeModelData? modelData;
    if (json['modelBrand'] != null && json['modelName'] != null) {
      modelData = EBikeModelData(
        brand: json['modelBrand'] as String,
        model: json['modelName'] as String,
        type: EBikeType.eBike,
        defaultMotor: json['motor'] as String?,
        defaultController: json['controller'] as String?,
        defaultBattery: json['battery'] as String?,
      );
    }

    return EBike(
      id: json['id'].toString(),
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
      traxSerialNumber: json['traxSerialNumber'] as String?,
      motor: json['motor'] as String? ?? '',
      controller: json['controller'] as String? ?? '',
      battery: json['battery'] as String? ?? '',
      motorCertified: json['motorCertified'] as bool? ?? false,
      controllerCertified: json['controllerCertified'] as bool? ?? false,
      batteryCertified: json['batteryCertified'] as bool? ?? false,
      modelData: modelData,
      type: null,
      other: json['other'] as String?,
      isConnected: json['connected'] as bool? ?? json['isConnected'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

