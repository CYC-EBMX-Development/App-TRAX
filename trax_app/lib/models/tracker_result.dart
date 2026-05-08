class TrackerResult {
  final String serialNumber;
  final String? motor;
  final String? controller;
  final String? battery;
  final bool motorCertified;
  final bool controllerCertified;
  final bool batteryCertified;
  final String? modelBrand;
  final String? modelName;

  const TrackerResult({
    required this.serialNumber,
    this.motor,
    this.controller,
    this.battery,
    this.motorCertified = false,
    this.controllerCertified = false,
    this.batteryCertified = false,
    this.modelBrand,
    this.modelName,
  });

  bool get hasAnyComponentData => motor != null || controller != null || battery != null;
  bool get hasAnyCertifiedData => motorCertified || controllerCertified || batteryCertified;
  bool get hasModelData => modelBrand != null && modelName != null;
}

