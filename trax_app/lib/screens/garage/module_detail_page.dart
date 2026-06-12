import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../common/services/module_ctrl_ws_client.dart';
import '../../common/services/module_imu_ws_client.dart';
import '../../common/services/module_telemetry_ws_client.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../models/ctrl_frame.dart';
import '../../models/imu_frame.dart';
import '../../models/module_telemetry.dart';
import '../../theme/app_theme.dart';

/// Live diagnostics page for a single bound TRA-X module. Three tabs:
///   • IMU  — accel / gyro / orientation / quaternion (200-sample
///            rolling window, ~50 Hz)
///   • GPS  — latitude / longitude / speed / signal / battery streamed
///            over `/ws/modules/{serialNo}/telemetry`.
///   • CTRL — controller telemetry (temp / current / voltage / duty /
///            throttle / regen) streamed over `/ws/modules/{serialNo}/ctrl`.
///            Live-only — NOT persisted here (ride recording is handled
///            server-side by CtrlIngestService).
class ModuleDetailPage extends StatelessWidget {
  final String serialNo;
  final String bikeName;
  const ModuleDetailPage({
    super.key,
    required this.serialNo,
    required this.bikeName,
  });

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '204', child: _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Module · $bikeName',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              Text(serialNo,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w400)),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'IMU'),
              Tab(text: 'GPS'),
              Tab(text: 'CTRL'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _ImuTab(serialNo: serialNo),
              _GpsTab(serialNo: serialNo),
              _CtrlTab(serialNo: serialNo),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// IMU tab
// ---------------------------------------------------------------------------

class _ImuTab extends StatefulWidget {
  final String serialNo;
  const _ImuTab({required this.serialNo});

  @override
  State<_ImuTab> createState() => _ImuTabState();
}

class _ImuTabState extends State<_ImuTab>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPoints = 200;

  late final ModuleImuWsClient _ws;
  StreamSubscription<ImuFrame>? _sub;

  final Queue<double> _ax = ListQueue(_maxPoints);
  final Queue<double> _ay = ListQueue(_maxPoints);
  final Queue<double> _az = ListQueue(_maxPoints);
  final Queue<double> _gx = ListQueue(_maxPoints);
  final Queue<double> _gy = ListQueue(_maxPoints);
  final Queue<double> _gz = ListQueue(_maxPoints);
  final Queue<double> _roll = ListQueue(_maxPoints);
  final Queue<double> _pitch = ListQueue(_maxPoints);
  final Queue<double> _yaw = ListQueue(_maxPoints);

  ImuFrame? _latest;
  DateTime? _lastFrameAt;
  int _frameCount = 0;
  DateTime _windowStart = DateTime.now();
  double _hz = 0;
  Timer? _hzTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ws = ModuleImuWsClient(serialNo: widget.serialNo);
    _sub = _ws.stream.listen(_onFrame);
    _ws.connect();
    _hzTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final dt = now.difference(_windowStart).inMilliseconds / 1000.0;
      if (mounted) {
        // setState every tick so the status strip can flip to 'offline'
        // when no new frame arrives within the staleness window.
        setState(() {
          if (dt > 0) _hz = _frameCount / dt;
        });
      }
      _frameCount = 0;
      _windowStart = now;
    });
  }

  @override
  void dispose() {
    _hzTimer?.cancel();
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }

  void _push(Queue<double> q, double v) {
    if (q.length >= _maxPoints) q.removeFirst();
    q.addLast(v);
  }

  void _onFrame(ImuFrame f) {
    _push(_ax, f.ax); _push(_ay, f.ay); _push(_az, f.az);
    _push(_gx, f.gx); _push(_gy, f.gy); _push(_gz, f.gz);
    _push(_roll, f.roll); _push(_pitch, f.pitch); _push(_yaw, f.yaw);
    _frameCount++;
    _lastFrameAt = DateTime.now();
    if (mounted) setState(() => _latest = f);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _StatusStrip(
            connected: _ws.isConnected,
            live: _isLive(_lastFrameAt),
            trailing: '${_hz.toStringAsFixed(1)} Hz',
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Acceleration (m/s²)',
            seriesLabels: const ['ax', 'ay', 'az'],
            colors: const [
              Color(0xFFEF4444),
              Color(0xFF22C55E),
              Color(0xFF3B82F6),
            ],
            buffers: [_ax, _ay, _az],
            liveValues: _latest == null
                ? const [0, 0, 0]
                : [_latest!.ax, _latest!.ay, _latest!.az],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Gyroscope (rad/s)',
            seriesLabels: const ['gx', 'gy', 'gz'],
            colors: const [
              Color(0xFFEF4444),
              Color(0xFF22C55E),
              Color(0xFF3B82F6),
            ],
            buffers: [_gx, _gy, _gz],
            liveValues: _latest == null
                ? const [0, 0, 0]
                : [_latest!.gx, _latest!.gy, _latest!.gz],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Orientation (°)',
            seriesLabels: const ['roll', 'pitch', 'yaw'],
            colors: const [
              Color(0xFFEF4444),
              Color(0xFF22C55E),
              Color(0xFF3B82F6),
            ],
            buffers: [_roll, _pitch, _yaw],
            liveValues: _latest == null
                ? const [0, 0, 0]
                : [_latest!.roll, _latest!.pitch, _latest!.yaw],
          ),
          const SizedBox(height: 12),
          _QuaternionCard(latest: _latest),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GPS tab
// ---------------------------------------------------------------------------

class _GpsTab extends StatefulWidget {
  final String serialNo;
  const _GpsTab({required this.serialNo});

  @override
  State<_GpsTab> createState() => _GpsTabState();
}

class _GpsTabState extends State<_GpsTab>
    with AutomaticKeepAliveClientMixin {
  static const int _maxPoints = 200;

  late final ModuleTelemetryWsClient _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  final Queue<double> _speed = ListQueue(_maxPoints);
  final Queue<double> _signal = ListQueue(_maxPoints);

  ModuleTelemetry? _latest;
  DateTime? _lastFrameAt;
  int _frameCount = 0;
  DateTime _windowStart = DateTime.now();
  double _hz = 0;
  Timer? _hzTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ws = ModuleTelemetryWsClient(serialNo: widget.serialNo);
    _sub = _ws.stream.listen(_onJson);
    _ws.connect();
    _hzTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final dt = now.difference(_windowStart).inMilliseconds / 1000.0;
      if (mounted) {
        setState(() {
          if (dt > 0) _hz = _frameCount / dt;
        });
      }
      _frameCount = 0;
      _windowStart = now;
    });
  }

  @override
  void dispose() {
    _hzTimer?.cancel();
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }

  void _push(Queue<double> q, double v) {
    if (q.length >= _maxPoints) q.removeFirst();
    q.addLast(v);
  }

  void _onJson(Map<String, dynamic> json) {
    try {
      final t = ModuleTelemetry.fromJson(json);
      _push(_speed, t.speed);
      _push(_signal, t.signalStrength.toDouble());
      _frameCount++;
      _lastFrameAt = DateTime.now();
      if (mounted) setState(() => _latest = t);
    } catch (_) {
      /* ignore malformed */
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = _latest;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _StatusStrip(
            connected: _ws.isConnected,
            live: _isLive(_lastFrameAt),
            trailing: '${_hz.toStringAsFixed(1)} Hz',
          ),
          const SizedBox(height: 12),
          _GpsPositionCard(latest: t),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Speed (km/h)',
            seriesLabels: const ['speed'],
            colors: const [Color(0xFF3B82F6)],
            buffers: [_speed],
            liveValues: [t?.speed ?? 0],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Signal strength',
            seriesLabels: const ['signal'],
            colors: const [Color(0xFF22C55E)],
            buffers: [_signal],
            liveValues: [(t?.signalStrength ?? 0).toDouble()],
          ),
          const SizedBox(height: 12),
          _BatteryCard(latest: t),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GpsPositionCard extends StatelessWidget {
  final ModuleTelemetry? latest;
  const _GpsPositionCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final t = latest;
    Widget cell(String k, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(v,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Position',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            cell('Latitude', t == null ? '—' : t.latitude.toStringAsFixed(6)),
            cell('Longitude', t == null ? '—' : t.longitude.toStringAsFixed(6)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell('Speed',
                t == null ? '—' : '${t.speed.toStringAsFixed(2)} km/h'),
            cell('Signal',
                t == null ? '—' : '${t.signalStrength}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell('Satellites',
                t?.satellites == null ? '—' : '${t!.satellites}'),
            cell('Altitude',
                t?.altitude == null ? '—' : '${t!.altitude!.toStringAsFixed(1)} m'),
          ]),
          if (t?.timestamp != null) ...[
            const SizedBox(height: 8),
            Text('ts: ${t!.timestamp}',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final ModuleTelemetry? latest;
  const _BatteryCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final pct = latest?.batteryPercent ?? 0;
    final hasData = latest != null;
    final color = !hasData
        ? AppColors.textSecondary
        : (pct >= 50
            ? AppColors.success
            : (pct >= 20 ? Colors.amber : AppColors.error));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.battery_full, color: color, size: 22),
          const SizedBox(width: 10),
          const Text('Battery',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Text(hasData ? '$pct%' : '—',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CTRL tab
// ---------------------------------------------------------------------------

class _CtrlTab extends StatefulWidget {
  final String serialNo;
  const _CtrlTab({required this.serialNo});

  @override
  State<_CtrlTab> createState() => _CtrlTabState();
}

class _CtrlTabState extends State<_CtrlTab>
    with AutomaticKeepAliveClientMixin {
  // ~40 s window at 5 Hz. Bounds memory regardless of how long the page is
  // left open, so the chart never accumulates unbounded data.
  static const int _maxPoints = 200;

  late final ModuleCtrlWsClient _ws;
  StreamSubscription<CtrlFrame>? _sub;

  final Queue<double> _tempFet = ListQueue(_maxPoints);
  final Queue<double> _tempMotor = ListQueue(_maxPoints);
  final Queue<double> _currentMotor = ListQueue(_maxPoints);
  final Queue<double> _currentInput = ListQueue(_maxPoints);
  final Queue<double> _vin = ListQueue(_maxPoints);
  final Queue<double> _duty = ListQueue(_maxPoints);
  final Queue<double> _throttle = ListQueue(_maxPoints);
  final Queue<double> _regen = ListQueue(_maxPoints);

  CtrlFrame? _latest;
  DateTime? _lastFrameAt;
  int _frameCount = 0;
  DateTime _windowStart = DateTime.now();
  double _hz = 0;
  Timer? _hzTimer;

  // Render-throttle: inbound ctrl frames arrive in bursts (the module batches
  // ~5 records per MQTT publish). We push to the ring buffers on EVERY frame
  // (cheap, no repaint) and repaint at a bounded ~6.7 Hz via this timer, so a
  // burst can never force a flood of fl_chart rebuilds and stutter the UI.
  bool _dirty = false;
  Timer? _repaintTimer;
  static const Duration _repaintInterval = Duration(milliseconds: 150);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ws = ModuleCtrlWsClient(serialNo: widget.serialNo);
    _sub = _ws.stream.listen(_onFrame);
    _ws.connect();
    _hzTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final dt = now.difference(_windowStart).inMilliseconds / 1000.0;
      if (mounted) {
        // Tick a setState so the status strip can flip to 'offline' when the
        // stream goes quiet, even if no new frame arrived this second.
        setState(() {
          if (dt > 0) _hz = _frameCount / dt;
        });
      }
      _frameCount = 0;
      _windowStart = now;
    });
    _repaintTimer = Timer.periodic(_repaintInterval, (_) {
      if (_dirty && mounted) {
        _dirty = false;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Cleanup on page exit: stop timers, cancel the stream, close the socket
    // (the WS client closes its StreamController), and let the ring buffers be
    // GC'd with this State. No cached ctrl data survives leaving the page.
    _repaintTimer?.cancel();
    _hzTimer?.cancel();
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }

  void _push(Queue<double> q, double v) {
    if (q.length >= _maxPoints) q.removeFirst();
    q.addLast(v);
  }

  void _onFrame(CtrlFrame f) {
    _push(_tempFet, f.tempFet ?? 0);
    _push(_tempMotor, f.tempMotor ?? 0);
    _push(_currentMotor, f.currentMotor ?? 0);
    _push(_currentInput, f.currentInput ?? 0);
    _push(_vin, f.vin ?? 0);
    _push(_duty, f.duty ?? 0);
    _push(_throttle, f.throttle ?? 0);
    _push(_regen, f.regen ?? 0);
    _frameCount++;
    _lastFrameAt = DateTime.now();
    _latest = f;
    _dirty = true; // repaint is flushed by _repaintTimer, not here
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final f = _latest;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _StatusStrip(
            connected: _ws.isConnected,
            live: _isLive(_lastFrameAt),
            trailing: '${_hz.toStringAsFixed(1)} Hz',
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Temperature (°C)',
            seriesLabels: const ['fet', 'motor'],
            colors: const [Color(0xFFEF4444), Color(0xFFF59E0B)],
            buffers: [_tempFet, _tempMotor],
            liveValues: [f?.tempFet ?? 0, f?.tempMotor ?? 0],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Current (A)',
            seriesLabels: const ['motor', 'input'],
            colors: const [Color(0xFFEF4444), Color(0xFF3B82F6)],
            buffers: [_currentMotor, _currentInput],
            liveValues: [f?.currentMotor ?? 0, f?.currentInput ?? 0],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Input voltage (V)',
            seriesLabels: const ['v_in'],
            colors: const [Color(0xFF22C55E)],
            buffers: [_vin],
            liveValues: [f?.vin ?? 0],
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Duty / Throttle / Regen',
            seriesLabels: const ['duty', 'throttle', 'regen'],
            colors: const [
              Color(0xFF8B5CF6),
              Color(0xFF22C55E),
              Color(0xFFEF4444),
            ],
            buffers: [_duty, _throttle, _regen],
            liveValues: [
              f?.duty ?? 0,
              f?.throttle ?? 0,
              f?.regen ?? 0,
            ],
          ),
          const SizedBox(height: 12),
          _CtrlAdvancedCard(latest: f),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// d-q axis currents/voltages shown as latest values (not charted, to keep
/// the page light). These are advanced FOC internals most riders won't chart.
class _CtrlAdvancedCard extends StatelessWidget {
  final CtrlFrame? latest;
  const _CtrlAdvancedCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final f = latest;
    Widget cell(String k, double? v) => Expanded(
          child: Column(
            children: [
              Text(k,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(v == null ? '—' : v.toStringAsFixed(3),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FOC (d-q axis)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            cell('id', f?.id),
            cell('iq', f?.iq),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            cell('vd', f?.vd),
            cell('vq', f?.vq),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

/// Module-signal staleness window. Mirrors the frame-presence criterion used
/// by ride flows (e.g. `LocationSignalGate`, `free_ride_page._onMyLocationTap`)
/// — "module online" = decoded frame received within the last N seconds, NOT
/// just WebSocket TCP handshake state.
const Duration _kLiveWindow = Duration(seconds: 5);

bool _isLive(DateTime? lastFrameAt) {
  if (lastFrameAt == null) return false;
  return DateTime.now().difference(lastFrameAt) <= _kLiveWindow;
}

class _StatusStrip extends StatelessWidget {
  final bool connected;
  final bool live;
  final String? trailing;
  const _StatusStrip({
    required this.connected,
    required this.live,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = live
        ? AppColors.success
        : (connected ? AppColors.error : AppColors.textSecondary);
    final label = !connected
        ? 'Connecting…'
        : (live ? 'Live' : 'Module offline');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600)),
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing!,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<String> seriesLabels;
  final List<Color> colors;
  final List<Queue<double>> buffers;
  final List<double> liveValues;

  const _ChartCard({
    required this.title,
    required this.seriesLabels,
    required this.colors,
    required this.buffers,
    required this.liveValues,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < seriesLabels.length; i++) ...[
                _Legend(
                    label: seriesLabels[i],
                    color: colors[i],
                    value: liveValues[i]),
                if (i < seriesLabels.length - 1) const SizedBox(width: 14),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 140,
            child: _LineChart(buffers: buffers, colors: colors),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  final double value;
  const _Legend({
    required this.label,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        Text(value.toStringAsFixed(2),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<Queue<double>> buffers;
  final List<Color> colors;
  const _LineChart({required this.buffers, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (buffers.first.isEmpty) {
      return const Center(
        child: Text('No data',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final b in buffers) {
      for (final v in b) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.08;

    final bars = <LineChartBarData>[];
    for (var i = 0; i < buffers.length; i++) {
      final b = buffers[i];
      final spots = <FlSpot>[];
      var x = 0;
      for (final v in b) {
        spots.add(FlSpot(x.toDouble(), v));
        x++;
      }
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 1.5,
        color: colors[i],
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        minX: 0,
        maxX: (buffers.first.length - 1).toDouble().clamp(1, double.infinity),
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval:
              ((maxY - minY) / 4).abs().clamp(0.001, double.infinity),
          getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.divider.withValues(alpha: 0.4),
              strokeWidth: 0.5),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: Duration.zero,
    );
  }
}

class _QuaternionCard extends StatelessWidget {
  final ImuFrame? latest;
  const _QuaternionCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    final f = latest;
    Widget cell(String k, double v) => Expanded(
          child: Column(
            children: [
              Text(k,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(v.toStringAsFixed(3),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quaternion',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            cell('q0', f?.q0 ?? 0),
            cell('q1', f?.q1 ?? 0),
            cell('q2', f?.q2 ?? 0),
            cell('q3', f?.q3 ?? 0),
          ]),
          if (f?.timestamp != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text('ts: ${f!.timestamp}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }
}
