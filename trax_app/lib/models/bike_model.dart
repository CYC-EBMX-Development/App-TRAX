class BikeModel {
  final int id;
  final String modelName;
  final String? motorType;
  final String? controller;
  final String? imageUrl;
  final String brandName;
  final int? motorPeakPowerW;
  final int? motorTorqueNm;
  final String? batteryType;
  final String? batteryVoltage;
  final int? batteryCapacityWh;

  BikeModel({
    required this.id,
    required this.modelName,
    this.motorType,
    this.controller,
    this.imageUrl,
    required this.brandName,
    this.motorPeakPowerW,
    this.motorTorqueNm,
    this.batteryType,
    this.batteryVoltage,
    this.batteryCapacityWh,
  });

  factory BikeModel.fromJson(Map<String, dynamic> json) {
    return BikeModel(
      id: json['id'] as int,
      modelName: json['modelName'] as String,
      motorType: json['motorType'] as String?,
      controller: json['controller'] as String?,
      imageUrl: json['imageUrl'] as String?,
      brandName: json['brandName'] as String,
      motorPeakPowerW: json['motorPeakPowerW'] as int?,
      motorTorqueNm: json['motorTorqueNm'] as int?,
      batteryType: json['batteryType'] as String?,
      batteryVoltage: json['batteryVoltage'] as String?,
      batteryCapacityWh: json['batteryCapacityWh'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'modelName': modelName,
      'motorType': motorType,
      'controller': controller,
      'imageUrl': imageUrl,
      'brandName': brandName,
      'motorPeakPowerW': motorPeakPowerW,
      'motorTorqueNm': motorTorqueNm,
      'batteryType': batteryType,
      'batteryVoltage': batteryVoltage,
      'batteryCapacityWh': batteryCapacityWh,
    };
  }
}
