

class DataResult {
  final String id;
  final double torque; // Nm
  final double angle; // graus (ou unidade definida)
  final String type; // ex: "TQ", "FR", "TV"
  final int? sampleTimeMs;
  final int? thresholdDir;
  final int? resultDir;

  DataResult({
    required this.id,
    required this.torque,
    required this.angle,
    required this.type,
    this.sampleTimeMs,
    this.thresholdDir,
    this.resultDir,
  });

  @override
  String toString() {
    return 'DataResult(id:$id, type:$type, torque:${torque.toStringAsFixed(3)} Nm, angle:${angle.toStringAsFixed(3)}°, sampleTimeMs:$sampleTimeMs)';
  }
}

class DataInformation {
  final String id;
  final String serialNumber;
  final String model;
  final String hw;
  final String fw;
  final String type; // DEVTYPE_TORQUEANGLE_ACQ / DEVTYPE_TORQUE_ACQ
  final String capacity;
  final int bufferSize;
  final double torqueConversionFactor;
  final double angleConversionFactor;

  DataInformation({
    required this.id,
    required this.serialNumber,
    required this.model,
    required this.hw,
    required this.fw,
    required this.type,
    required this.capacity,
    required this.bufferSize,
    required this.torqueConversionFactor,
    required this.angleConversionFactor,
  });

  @override
  String toString() {
    return 'DataInformation(id:$id, sn:$serialNumber, model:$model, hw:$hw, fw:$fw, type:$type, cap:$capacity, buf:$bufferSize, torqueConv:$torqueConversionFactor, angleConv:$angleConversionFactor)';
  }
}