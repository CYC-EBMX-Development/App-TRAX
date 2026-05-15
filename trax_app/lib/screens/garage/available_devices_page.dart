import 'dart:math';

import 'package:flutter/material.dart';
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
  String? _connectingId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
      _errorMessage = null;
    });

    // Fetch all modules from backend
    final resp = await TraxApi.getTraxModules();

    if (!mounted) return;

    if (!resp.isSuccess() || resp.data == null) {
      setState(() {
        _scanning = false;
        _errorMessage = 'Failed to scan: ${resp.message}';
      });
      return;
    }

    final List<dynamic> raw = resp.data as List<dynamic>;
    final modules = raw
        .map((m) => _ApiDevice.fromJson(m as Map<String, dynamic>))
        .toList();

    // Simulate progressive BT discovery — reveal devices one by one
    final rng = Random();
    final delays = [900, 500, 400];
    for (int i = 0; i < modules.length; i++) {
      final delay = i < delays.length ? delays[i] : 300 + rng.nextInt(400);
      await Future.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        modules[i].rssi = -60 - rng.nextInt(30); // simulate signal strength
        _devices.add(modules[i]);
        if (i == modules.length - 1) _scanning = false;
      });
    }
    if (mounted && modules.isEmpty) setState(() => _scanning = false);
  }

  Future<void> _onDeviceTap(_ApiDevice device) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = device.serialNo);

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
      content: '$serialNo is already registered to another account. Please use a different module.',
      mainBtnText: 'OK',
      mainBtnOnPressed: () => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '201', child: _buildContent(context));

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
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Text('Scanning for TRA-X modules…', style: TextStyle(fontSize: 13)),
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
              size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
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
        final isConnecting = _connectingId == device.serialNo;
        return _DeviceCard(
          device: device,
          isConnecting: isConnecting,
          onTap: () => _onDeviceTap(device),
        );
      },
    );
  }
}

class _ApiDevice {
  final String serialNo;
  final String name;
  final bool isBound;
  final String? motor;
  final String? controller;
  final String? battery;
  final bool motorCertified;
  final bool controllerCertified;
  final bool batteryCertified;
  final String? modelBrand;
  final String? modelName;
  int rssi = -70;

  _ApiDevice({
    required this.serialNo,
    required this.name,
    required this.isBound,
    this.motor,
    this.controller,
    this.battery,
    this.motorCertified = false,
    this.controllerCertified = false,
    this.batteryCertified = false,
    this.modelBrand,
    this.modelName,
  });

  factory _ApiDevice.fromJson(Map<String, dynamic> json) {
    return _ApiDevice(
      serialNo: json['serialNo'] as String,
      name: json['name'] as String,
      isBound: json['bound'] as bool? ?? false,
      motor: json['motor'] as String?,
      controller: json['controller'] as String?,
      battery: json['battery'] as String?,
      motorCertified: json['motorCertified'] as bool? ?? false,
      controllerCertified: json['controllerCertified'] as bool? ?? false,
      batteryCertified: json['batteryCertified'] as bool? ?? false,
      modelBrand: json['modelBrand'] as String?,
      modelName: json['modelName'] as String?,
    );
  }

  bool get isCycDevice => motor?.contains('CYC') == true;
  int get signalBars => rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
}

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
                child: Icon(Icons.bluetooth, size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name with binding indicator
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
                    // Serial No line
                    Text(
                      'Serial No: ${device.serialNo}',
                      style: TextStyle(
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
              // Signal indicator (single icon) + loading/chevron
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
                    Icon(
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
