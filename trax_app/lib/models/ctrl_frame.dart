/// Live controller-telemetry sample broadcast from backend at
/// `/ws/modules/{serialNo}/ctrl`. Mirrors `com.cyc.iot.common.model.CtrlFrame`
/// (12 decoded fields).
///
/// All metric fields are nullable: the firmware may emit a truncated frame,
/// and the chart layer treats nulls as gaps / zeros.
class CtrlFrame {
  final String serialNo;
  final String? timestamp;
  final double? tempFet;
  final double? tempMotor;
  final double? currentMotor;
  final double? currentInput;
  final double? id; // avg_id (d-axis)
  final double? iq; // avg_iq (q-axis)
  final double? duty;
  final double? vin;
  final double? throttle;
  final double? regen;
  final double? vd;
  final double? vq;

  const CtrlFrame({
    required this.serialNo,
    this.timestamp,
    this.tempFet,
    this.tempMotor,
    this.currentMotor,
    this.currentInput,
    this.id,
    this.iq,
    this.duty,
    this.vin,
    this.throttle,
    this.regen,
    this.vd,
    this.vq,
  });

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }

  factory CtrlFrame.fromJson(Map<String, dynamic> j) => CtrlFrame(
        serialNo: j['serialNo'] as String? ?? '',
        timestamp: j['ts'] as String?,
        tempFet: _d(j['temp_fet']),
        tempMotor: _d(j['temp_motor']),
        currentMotor: _d(j['current_motor']),
        currentInput: _d(j['current_input']),
        id: _d(j['id']),
        iq: _d(j['iq']),
        duty: _d(j['duty']),
        vin: _d(j['v_in']),
        throttle: _d(j['throttle']),
        regen: _d(j['regen']),
        vd: _d(j['vd']),
        vq: _d(j['vq']),
      );
}
