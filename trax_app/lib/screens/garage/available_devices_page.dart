import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../common/ble/ble_permission.dart';
import '../../common/ble/module_command_client.dart';
import '../../common/ble/trax_ble_scanner.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/tracker_result.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class AvailableDevicesPage extends StatefulWidget {
  const AvailableDevicesPage({super.key});

  @override
  State<AvailableDevicesPage> createState() => _AvailableDevicesPageState();
}

class _AvailableDevicesPageState extends State<AvailableDevicesPage> {
  bool _scanning = true;
  final List<_ApiDevice> _devices = [];
  // Serials we've already queried for bind-status during this scan session,
  // to avoid hammering the backend as scan results stream in.
  final Set<String> _checkedSerials = <String>{};
  String? _connectingId;
  String? _errorMessage;
  // Bumped on every new scan / on dispose so an in-flight username-resolution
  // loop can detect it's stale and bail out.
  int _scanToken = 0;
  // Serialises BLE connects so the post-scan username reads never overlap each
  // other or a user-initiated bind tap (only one GATT link at a time).
  Future<void> _bleLock = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanToken++;
    TraxBleScanner.instance.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    final token = ++_scanToken;
    setState(() {
      _scanning = true;
      _devices.clear();
      _checkedSerials.clear();
      _errorMessage = null;
    });

    // ── 1. Android: 用 permission_handler 申请定位/扫描/连接权限。
    //    iOS: 跳过 — 蓝牙授权完全由系统 CBManagerAuthorization 管理，
    //    permission_handler.Permission.bluetooth 的状态在 iOS 上不可靠
    //    （即使已授权，常常返回非 granted），会误报权限缺失。
    if (!kIsWeb && Platform.isAndroid) {
      final errors = await BlePermission.checkPerm();
      if (!mounted) return;
      if (errors.isNotEmpty) {
        TraxDialog.showBottomTipsDialog(
          title: 'Nearby devices permission required',
          content:
              'TRAX needs Bluetooth and Location to find and pair with TRA-X '
              'modules. Enable them in system Settings, then return and tap Retry.',
          mainBtnText: 'Go to Settings',
          mainBtnOnPressed: () {
            Navigator.of(context).pop();
            openAppSettings();
          },
          subBtnText: 'Cancel',
        );
        setState(() {
          _scanning = false;
          _errorMessage = 'Bluetooth permission not granted.';
        });
        return;
      }
    }

    // ── 2. 检查蓝牙状态 (覆盖 iOS 授权 + 双端开关)
    //    首次调用时 iOS CBCentralManager 可能还没回调 didUpdateState，
    //    会返回 unknown。最多等 2s 让真实状态到达。
    var btState = await UniversalBle.getBluetoothAvailabilityState();
    if (btState == AvailabilityState.unknown) {
      btState = await UniversalBle.availabilityStream
          .firstWhere((s) => s != AvailabilityState.unknown)
          .timeout(const Duration(seconds: 2), onTimeout: () => btState);
    }
    if (!mounted) return;

    if (btState == AvailabilityState.unauthorized) {
      TraxDialog.showBottomTipsDialog(
        title: 'Bluetooth permission required',
        content:
            'TRAX needs Bluetooth access to find and pair with TRA-X modules. '
            'Enable it in system Settings → TRAX → Bluetooth, then return and tap Retry.',
        mainBtnText: 'Go to Settings',
        mainBtnOnPressed: () {
          Navigator.of(context).pop();
          openAppSettings();
        },
        subBtnText: 'Cancel',
      );
      setState(() {
        _scanning = false;
        _errorMessage = 'Bluetooth permission not granted.';
      });
      return;
    }

    if (btState == AvailabilityState.poweredOff) {
      TraxDialog.showBottomTipsDialog(
        title: 'Bluetooth is Off',
        content: 'Enable Bluetooth to scan for nearby TRA-X modules.',
        mainBtnText: 'Open Settings',
        mainBtnOnPressed: () {
          Navigator.of(context).pop();
          openAppSettings();
        },
        subBtnText: 'Cancel',
      );
      setState(() {
        _scanning = false;
        _errorMessage = 'Bluetooth is turned off.';
      });
      return;
    }

    if (btState != AvailabilityState.poweredOn) {
      setState(() {
        _scanning = false;
        _errorMessage = 'Bluetooth unavailable ($btState).';
      });
      return;
    }

    // ── 3. 真实 BLE 扫描，渐进式显示 ────────────────────────────────────
    await TraxBleScanner.instance.startScan(
      scanDuration: const Duration(seconds: 10),
      onDeviceFound: (BleDevice ble, bool isNew) {
        if (!mounted) return;
        final bleName = (ble.name != null && ble.name!.isNotEmpty)
            ? ble.name!
            : null;
        final newRssi = ble.rssi ?? -70;
        setState(() {
          // Distinguish devices by BLE deviceId, NOT by advertised name:
          // multiple physical modules can share the same Local Name
          // (e.g. several EBMX_TRACKER_02 on the bench), so the deviceId is
          // the only reliable per-device identity. Each distinct deviceId
          // gets its own card.
          final idx =
              _devices.indexWhere((d) => d.deviceId == ble.deviceId);

          if (idx == -1) {
            _devices.add(_ApiDevice.fromBle(ble));
            // Sort once on insertion so stronger signals surface first; we do
            // NOT re-sort on later RSSI updates, otherwise the cards keep
            // swapping places as RSSI fluctuates and the list appears to
            // "re-scan" / flicker on every advertisement packet.
            _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
          } else {
            final cur = _devices[idx];
            // Same device, later ad packet: refresh RSSI and pick up the name
            // if it only arrived now. deviceId is the stable key — never
            // changed here.
            final newName = bleName ?? cur.name;
            _devices[idx] = cur.copyWith(
              rssi: newRssi > cur.rssi ? newRssi : cur.rssi,
              name: newName,
              serialNo: newName,
            );
          }
        });
        // Fire a background bind-status check for any newly-seen serial.
        // Non-awaited; UI just updates when the response arrives.
        unawaited(_refreshBoundStatus());
      },
    );

    // Final sweep after scan ends — picks up anything missed mid-stream.
    await _refreshBoundStatus();

    if (mounted) setState(() => _scanning = false);

    // Now that scanning has stopped (radio is free), read each module's real
    // MQTT username so the list can show it instead of the opaque device id.
    unawaited(_resolveUsernames(token));
  }

  /// Queries the backend for which of the currently-resolved usernames are
  /// already bound to a bicycle and flips the {@code isBound} flag in place.
  /// Each username is queried at most once per scan session. The bound serial
  /// stored on the backend IS the module's MQTT username (e.g.
  /// express_4118e0ae), so we match on username, not the advertised BLE name.
  Future<void> _refreshBoundStatus() async {
    final pending = _devices
        .map((d) => d.username)
        .whereType<String>()
        .where((s) => s.isNotEmpty && !_checkedSerials.contains(s))
        .toSet()
        .toList();
    if (pending.isEmpty) return;
    _checkedSerials.addAll(pending);

    final resp = await TraxApi.checkBoundSerials(pending);
    if (!mounted || !resp.isSuccess()) return;
    final data = resp.data;
    if (data is! Map) return;
    final boundRaw = data['bound'];
    if (boundRaw is! List) return;
    final bound = boundRaw.whereType<String>().toSet();
    if (bound.isEmpty) return;

    setState(() {
      for (var i = 0; i < _devices.length; i++) {
        final u = _devices[i].username;
        if (u != null && bound.contains(u) && !_devices[i].isBound) {
          _devices[i] = _devices[i].copyWith(isBound: true);
        }
      }
    });
  }

  /// After scanning stops, connect to each discovered module one-at-a-time to
  /// read its MQTT username (its real serial, e.g. express_4118e0ae) so the
  /// list shows that instead of the opaque BLE device id. Aborts if the page
  /// is disposed, a new scan starts ([token] goes stale), or the user starts a
  /// bind tap.
  Future<void> _resolveUsernames(int token) async {
    for (var i = 0; i < _devices.length; i++) {
      if (!mounted || token != _scanToken) return;
      if (_connectingId != null) return; // user is binding — don't compete.
      final dev = _devices[i];
      if (dev.username != null || dev.usernameLoading) continue;

      setState(() {
        final idx = _devices.indexWhere((d) => d.deviceId == dev.deviceId);
        if (idx != -1) {
          _devices[idx] = _devices[idx].copyWith(usernameLoading: true);
        }
      });

      final result = await _resolveUsername(dev.deviceId);
      if (!mounted || token != _scanToken) return;

      setState(() {
        final idx = _devices.indexWhere((d) => d.deviceId == dev.deviceId);
        if (idx == -1) return;
        _devices[idx] = _devices[idx].copyWith(
          username: result.isSuccess ? result.username : null,
          usernameLoading: false,
        );
      });

      // A freshly-resolved username can now be bound-checked.
      if (result.isSuccess) unawaited(_refreshBoundStatus());
    }
  }

  /// Serialised single-device username read — guarantees only one GATT link is
  /// open at a time (via [_bleLock]).
  Future<ModuleUsernameResult> _resolveUsername(String deviceId) {
    final out = Completer<ModuleUsernameResult>();
    _bleLock = _bleLock.then((_) async {
      if (!mounted) {
        if (!out.isCompleted) {
          out.complete(ModuleUsernameResult.failure('Cancelled'));
        }
        return;
      }
      final r =
          await TraxModuleCommandClient.instance.queryMqttUsername(deviceId);
      if (!out.isCompleted) out.complete(r);
    }).catchError((Object e) {
      if (!out.isCompleted) {
        out.complete(ModuleUsernameResult.failure('Read failed: $e'));
      }
    });
    return out.future;
  }

  Future<void> _onDeviceTap(_ApiDevice device) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = device.deviceId);

    // 1. Bound-check first — no point burning a GATT connect on a module
    //    that's already owned by someone else.
    if (device.isBound) {
      setState(() => _connectingId = null);
      _showBoundAlert(device.username ?? device.name);
      return;
    }

    // 2. Reuse the username we already read during the post-scan resolve if we
    //    have it; otherwise pause scanning and read it now over the SPP
    //    command channel. The username (= the module's certificate CN /
    //    cloud id) is the prefix every telemetry topic is keyed by, so it must
    //    come from the module itself — it can't be guessed or typed.
    String? username = device.username;
    if (username == null) {
      await TraxBleScanner.instance.stopScan();
      if (!mounted) return;

      final usernameResult = await _resolveUsername(device.deviceId);
      if (!mounted) return;

      if (!usernameResult.isSuccess) {
        setState(() => _connectingId = null);
        TraxDialog.showBottomTipsDialog(
          title: 'Could not read module',
          content:
              '${usernameResult.error ?? 'Unknown error.'}\n\nMake sure the module '
              'is powered on and within a few metres of the phone, then try again.',
          mainBtnText: 'OK',
          mainBtnOnPressed: () => Navigator.of(context).pop(),
        );
        return;
      }
      username = usernameResult.username;
    }
    setState(() => _connectingId = null);

    final result = TrackerResult(
      serialNumber: username!,
      motor: device.motor,
      controller: device.controller,
      battery: device.battery,
      motorCertified: device.motorCertified,
      controllerCertified: device.controllerCertified,
      batteryCertified: device.batteryCertified,
      modelBrand: device.modelBrand,
      modelName: device.modelName,
    );

    if (mounted) Navigator.of(context).pop(result);
  }

  void _showBoundAlert(String serialNo) {
    TraxDialog.showBottomTipsDialog(
      title: 'Module already bound',
      content:
          '$serialNo is already registered to another account. Please use a different module.',
      mainBtnText: 'OK',
      mainBtnOnPressed: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '201', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Available devices'),
        actions: [
          if (!_scanning)
            TextButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Scan'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) _buildScanningBanner(),
          Expanded(
            child: _errorMessage != null
                ? _buildError()
                : _devices.isEmpty && !_scanning
                    ? _buildEmpty()
                    : _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Text('Scanning for TRA-X modules…',
              style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_searching,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('No modules found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Make sure your TRA-X module is powered on',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan again'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 56, color: AppColors.error.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(_errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final device = _devices[i];
        final isConnecting = _connectingId == device.deviceId;
        return _DeviceCard(
          // Key on the deviceId — it's the stable per-device identity and is
          // unique even when several modules share the same advertised name.
          key: ValueKey(device.deviceId),
          device: device,
          isConnecting: isConnecting,
          onTap: () => _onDeviceTap(device),
        );
      },
    );
  }
}

// ── 设备数据模型 ────────────────────────────────────────────────────────────
// 对 BleDevice 做一层封装，保持与原有 UI（_DeviceCard）完全兼容。

class _ApiDevice {
  final String deviceId; // BLE device ID
  final String serialNo; // 显示用序列号（= BLE name）
  final String name;     // 显示名称
  // Mutable across rebuilds via copyWith — flips true once the backend
  // tells us this serial is already bound to a bicycle.
  final bool isBound;
  final String? motor;
  final String? controller;
  final String? battery;
  final bool motorCertified;
  final bool controllerCertified;
  final bool batteryCertified;
  final String? modelBrand;
  final String? modelName;
  int rssi;
  // The module's MQTT username (= its real serial, e.g. express_4118e0ae),
  // read live over BLE after scanning. Null until resolved.
  final String? username;
  // True while the post-scan resolver is connecting to read [username].
  final bool usernameLoading;

  _ApiDevice({
    required this.deviceId,
    required this.serialNo,
    required this.name,
    this.isBound = false,
    this.motor,
    this.controller,
    this.battery,
    this.motorCertified = false,
    this.controllerCertified = false,
    this.batteryCertified = false,
    this.modelBrand,
    this.modelName,
    this.rssi = -70,
    this.username,
    this.usernameLoading = false,
  });

  /// 从真实 BLE 扫描结果构建。名字常常缺失或重复（多台 tracker_02），
  /// 真正区分设备的是 deviceId，因此名字仅作标题展示，缺失时退回通用文案。
  factory _ApiDevice.fromBle(BleDevice ble) {
    final name = (ble.name != null && ble.name!.isNotEmpty)
        ? ble.name!
        : 'TRA-X module';
    return _ApiDevice(
      deviceId: ble.deviceId,
      serialNo: name,
      name: name,
      rssi: ble.rssi ?? -70,
    );
  }

  _ApiDevice copyWithRssi(int newRssi) => copyWith(rssi: newRssi);

  _ApiDevice copyWith({
    bool? isBound,
    int? rssi,
    String? name,
    String? serialNo,
    String? deviceId,
    String? username,
    bool? usernameLoading,
  }) =>
      _ApiDevice(
        deviceId: deviceId ?? this.deviceId,
        serialNo: serialNo ?? this.serialNo,
        name: name ?? this.name,
        isBound: isBound ?? this.isBound,
        motor: motor,
        controller: controller,
        battery: battery,
        motorCertified: motorCertified,
        controllerCertified: controllerCertified,
        batteryCertified: batteryCertified,
        modelBrand: modelBrand,
        modelName: modelName,
        rssi: rssi ?? this.rssi,
        username: username ?? this.username,
        usernameLoading: usernameLoading ?? this.usernameLoading,
      );

  /// Subtitle under the device name. Prefer the module's real MQTT username
  /// (its serial, e.g. express_4118e0ae) once read; show a hint while reading;
  /// fall back to the opaque BLE device id.
  String get subtitle {
    if (username != null && username!.isNotEmpty) return 'Serial No: $username';
    if (usernameLoading) return 'Serial No: reading…';
    return 'Device ID: $deviceId';
  }

  int get signalBars => rssi > -65 ? 3 : rssi > -75 ? 2 : 1;

  /// Rough line-of-sight distance (metres) estimated from RSSI using the
  /// log-distance path-loss model:  d = 10 ^ ((txPower - rssi) / (10 * n)).
  /// txPower = expected RSSI at 1 m, n = path-loss exponent (2 in free space,
  /// up to ~4 indoors). This is a coarse estimate — BLE RSSI is noisy and
  /// affected by orientation/obstacles — so it's shown as an approximation.
  double get estimatedDistanceMeters {
    const txPower = -59; // typical BLE advertiser RSSI at 1 m
    const n = 2.5; // indoor-ish path-loss exponent
    return math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  /// Human-readable distance label, e.g. "<1 m", "~2.4 m", "~15 m".
  String get distanceLabel {
    final d = estimatedDistanceMeters;
    if (d < 1) return '<1 m';
    if (d < 10) return '~${d.toStringAsFixed(1)} m';
    return '~${d.round()} m';
  }
}

// ── 卡片 UI（与原版完全一致） ────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final _ApiDevice device;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceCard(
      {super.key,
      required this.device,
      required this.isConnecting,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: InkWell(
        onTap: isConnecting ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(Icons.bluetooth, size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: device.isBound
                                  ? Colors.black38
                                  : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (device.isBound) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 12, color: AppColors.error),
                                const SizedBox(width: 3),
                                Text(
                                  'Occupied',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      device.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Estimated distance — shown to the LEFT of the signal indicator.
              Text(
                device.distanceLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
              // Signal strength: icon + raw RSSI in dBm.
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.signal_cellular_alt,
                    size: 18,
                    color: _getSignalColor(device.signalBars),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${device.rssi} dBm',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black38,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSignalColor(int signalBars) {
    if (signalBars >= 3) return AppColors.success;
    if (signalBars == 2) return Colors.orange;
    return Colors.red;
  }
}