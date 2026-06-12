/// Live IMU sample broadcast from backend at
/// `/ws/modules/{serialNo}/imu`. Mirrors `com.cyc.iot.common.model.ImuFrame`.
///
/// All double-typed fields default to 0 (or null for [timestamp]) if the
/// firmware emitted NaN / missing fields — the chart layer tolerates that.
class ImuFrame {
  final String serialNo;
  final String? timestamp;
  final double ax, ay, az;
  final double gx, gy, gz;
  final double roll, pitch, yaw;
  final double q0, q1, q2, q3;

  const ImuFrame({
    required this.serialNo,
    this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.q0,
    required this.q1,
    required this.q2,
    required this.q3,
  });

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : 0;
    }
    return 0;
  }

  factory ImuFrame.fromJson(Map<String, dynamic> j) => ImuFrame(
        serialNo: j['serialNo'] as String? ?? '',
        timestamp: j['ts'] as String?,
        ax: _d(j['ax']),
        ay: _d(j['ay']),
        az: _d(j['az']),
        gx: _d(j['gx']),
        gy: _d(j['gy']),
        gz: _d(j['gz']),
        roll: _d(j['roll']),
        pitch: _d(j['pitch']),
        yaw: _d(j['yaw']),
        q0: _d(j['q0']),
        q1: _d(j['q1']),
        q2: _d(j['q2']),
        q3: _d(j['q3']),
      );
}
