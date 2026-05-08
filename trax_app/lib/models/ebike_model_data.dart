enum EBikeType { eBike, eMotor }

extension EBikeTypeLabel on EBikeType {
  String get label => this == EBikeType.eBike ? 'E-Bike' : 'E-Motor';
}

class EBikeModelData {
  final String brand;
  final String model;
  final EBikeType type;
  final String? defaultMotor;
  final String? defaultController;
  final String? defaultBattery;

  const EBikeModelData({
    required this.brand,
    required this.model,
    required this.type,
    this.defaultMotor,
    this.defaultController,
    this.defaultBattery,
  });

  // Factory constructor to convert from BikeModel API response
  factory EBikeModelData.fromBikeModel(dynamic bikeModel) {
    // Import is deferred to avoid circular dependency - expect BikeModel structure
    // {id, modelName, motorType, controller, imageUrl, brandName, ...}
    return EBikeModelData(
      brand: bikeModel.brandName as String,
      model: bikeModel.modelName as String,
      type: EBikeType.eBike, // Assume API models are e-bikes
      defaultMotor: bikeModel.motorType as String?,
      defaultController: bikeModel.controller as String?,
      defaultBattery: bikeModel.batteryType as String?,
    );
  }
}

class EBikeModelCatalog {
  static const List<EBikeModelData> all = [
    // CYC Motor — E-Motor (TRA-X certified)
    EBikeModelData(brand: 'CYC Motor', model: 'X1 Pro Gen3', type: EBikeType.eMotor, defaultMotor: 'CYC X1 Pro Gen3'),
    EBikeModelData(brand: 'CYC Motor', model: 'X1 Pro Gen2', type: EBikeType.eMotor, defaultMotor: 'CYC X1 Pro Gen2'),
    EBikeModelData(brand: 'CYC Motor', model: 'X1 Stealth', type: EBikeType.eMotor, defaultMotor: 'CYC X1 Stealth'),
    EBikeModelData(brand: 'CYC Motor', model: 'X1 Pro Race', type: EBikeType.eMotor, defaultMotor: 'CYC X1 Pro Race'),

    // EBMX — E-Bike (TRA-X certified)
    EBikeModelData(brand: 'EBMX', model: 'EBMX FR', type: EBikeType.eBike, defaultMotor: 'EBMX FR Motor', defaultController: 'EBMX Controller V2'),
    EBikeModelData(brand: 'EBMX', model: 'EBMX MX', type: EBikeType.eBike, defaultMotor: 'EBMX MX Motor', defaultController: 'EBMX Controller V2'),

    // Bafang — E-Motor
    EBikeModelData(brand: 'Bafang', model: 'BBS02B 750W', type: EBikeType.eMotor, defaultMotor: 'Bafang BBS02B 750W'),
    EBikeModelData(brand: 'Bafang', model: 'BBSHD 1000W', type: EBikeType.eMotor, defaultMotor: 'Bafang BBSHD 1000W'),
    EBikeModelData(brand: 'Bafang', model: 'M600', type: EBikeType.eMotor, defaultMotor: 'Bafang M600'),
    EBikeModelData(brand: 'Bafang', model: 'Ultra M620', type: EBikeType.eMotor, defaultMotor: 'Bafang Ultra M620'),

    // Tongsheng — E-Motor
    EBikeModelData(brand: 'Tongsheng', model: 'TSDZ2 36V', type: EBikeType.eMotor, defaultMotor: 'Tongsheng TSDZ2 36V'),
    EBikeModelData(brand: 'Tongsheng', model: 'TSDZ2 48V', type: EBikeType.eMotor, defaultMotor: 'Tongsheng TSDZ2 48V'),
    EBikeModelData(brand: 'Tongsheng', model: 'TSDZ8', type: EBikeType.eMotor, defaultMotor: 'Tongsheng TSDZ8'),

    // Bosch — E-Motor
    EBikeModelData(brand: 'Bosch', model: 'Performance Line CX', type: EBikeType.eMotor, defaultMotor: 'Bosch Performance Line CX'),
    EBikeModelData(brand: 'Bosch', model: 'Performance Line Speed', type: EBikeType.eMotor, defaultMotor: 'Bosch Performance Line Speed'),
    EBikeModelData(brand: 'Bosch', model: 'Cargo Line', type: EBikeType.eMotor, defaultMotor: 'Bosch Cargo Line'),

    // Shimano — E-Motor
    EBikeModelData(brand: 'Shimano', model: 'EP8', type: EBikeType.eMotor, defaultMotor: 'Shimano EP8'),
    EBikeModelData(brand: 'Shimano', model: 'E8000', type: EBikeType.eMotor, defaultMotor: 'Shimano E8000'),
    EBikeModelData(brand: 'Shimano', model: 'E6100', type: EBikeType.eMotor, defaultMotor: 'Shimano E6100'),

    // Trek — E-Bike
    EBikeModelData(brand: 'Trek', model: 'Rail 9.9', type: EBikeType.eBike),
    EBikeModelData(brand: 'Trek', model: 'Powerfly 9 FS', type: EBikeType.eBike),
    EBikeModelData(brand: 'Trek', model: 'Fuel EXe', type: EBikeType.eBike),

    // Specialized — E-Bike
    EBikeModelData(brand: 'Specialized', model: 'Turbo Levo', type: EBikeType.eBike),
    EBikeModelData(brand: 'Specialized', model: 'Turbo Kenevo', type: EBikeType.eBike),
    EBikeModelData(brand: 'Specialized', model: 'Turbo Creo', type: EBikeType.eBike),

    // Giant — E-Bike
    EBikeModelData(brand: 'Giant', model: 'Trance X Advanced E+', type: EBikeType.eBike),
    EBikeModelData(brand: 'Giant', model: 'Reign E+ Pro', type: EBikeType.eBike),
    EBikeModelData(brand: 'Giant', model: 'Stance E+ Elite', type: EBikeType.eBike),
  ];

  static List<String> get brands {
    final seen = <String>{};
    return all.map((m) => m.brand).where(seen.add).toList();
  }

  static List<EBikeModelData> modelsForBrand(String brand) =>
      all.where((m) => m.brand == brand).toList();
}
