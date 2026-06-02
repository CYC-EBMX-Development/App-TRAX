import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../common/ble/ble_permission.dart';
import '../../common/ble/trax_ble_scanner.dart';
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
  String? _connectingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    TraxBleScanner.instance.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
      _errorMessage = null;
    });

    // ── 1. 检查蓝牙权限 ──────────────────────────────────────────────────
    final errors = await BlePermission.checkPerm();
    if (!mounted) return;

    if (errors.isNotEmpty) {
      TraxDialog.showBottomTipsDialog(
        title: 'Nearby devices permission required',
        content:
            'TRAX needs Bluetooth access to find and pair with TRA-X modules. '
            'Enable it in Settings → Apps → TRAX → Permissions.',
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

    // ── 2. 检查蓝牙开关 ──────────────────────────────────────────────────
    final btState = await UniversalBle.getBluetoothAvailabilityState();
    if (!mounted) return;

    if (btState == AvailabilityState.poweredOff) {
      TraxDialog.showBottomTipsDialog(
        title: 'Bluetooth is Off',
        content: 'Enable Bluetooth to scan for nearby TRA-X modules.',
        mainBtnText: 'Turn On Bluetooth',
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

    // ── 3. 真实 BLE 扫描，渐进式显示 ────────────────────────────────────
    await TraxBleScanner.instance.startScan(
      scanDuration: const Duration(seconds: 10),
      onDeviceFound: (BleDevice ble, bool isNew) {
        if (!mounted) return;
        setState(() {
          if (isNew) {
            _devices.add(_ApiDevice.fromBle(ble));
            _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
          } else {
            final idx =
                _devices.indexWhere((d) => d.deviceId == ble.deviceId);
            if (idx != -1) {
              _devices[idx] = _devices[idx].copyWithRssi(ble.rssi ?? -100);
              _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
            }
          }
        });
      },
    );

    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _onDeviceTap(_ApiDevice device) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = device.deviceId);

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (device.isBound) {
      setState(() => _connectingId = null);
      _showBoundAlert(device.serialNo);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _connectingId = null);

    final result = TrackerResult(
      serialNumber: device.serialNo,
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
  });

  /// 从真实 BLE 扫描结果构建
  factory _ApiDevice.fromBle(BleDevice ble) {
    final label = ble.name ?? ble.deviceId;
    return _ApiDevice(
      deviceId: ble.deviceId,
      serialNo: label,
      name: label,
      rssi: ble.rssi ?? -70,
    );
  }

  _ApiDevice copyWithRssi(int newRssi) => _ApiDevice(
        deviceId: deviceId,
        serialNo: serialNo,
        name: name,
        isBound: isBound,
        motor: motor,
        controller: controller,
        battery: battery,
        motorCertified: motorCertified,
        controllerCertified: controllerCertified,
        batteryCertified: batteryCertified,
        modelBrand: modelBrand,
        modelName: modelName,
        rssi: newRssi,
      );

  int get signalBars => rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
}

// ── 卡片 UI（与原版完全一致） ────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final _ApiDevice device;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceCard(
      {required this.device, required this.isConnecting, required this.onTap});

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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (device.isBound) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: AppColors.error.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Serial No: ${device.serialNo}',
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
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.signal_cellular_alt,
                    size: 16,
                    color: _getSignalColor(device.signalBars),
                  ),
                  const SizedBox(height: 4),
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