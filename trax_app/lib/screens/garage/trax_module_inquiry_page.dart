import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../models/tracker_result.dart';
import '../../theme/app_theme.dart';
import 'available_devices_page.dart';
import 'ebike_parts_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TraxModuleInquiryPage extends StatelessWidget {
  const TraxModuleInquiryPage({super.key});

  /// Server-configurable: whether to show the "Find a dealer" entry.
  /// TODO: replace with a value fetched from remote config.
  static const bool _showFindDealer = true;

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '205', child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Add a new bike'),
      ),
      body: Column(
        children: [
          Expanded(child: _buildContent()),
          _buildButtons(context),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          // TRA-X module icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.bluetooth, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 28),
          const Text(
            'Do you have a TRA-X Module?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'A TRA-X module connects directly to your eBike\'s motor system, '
            'allowing TRAX to automatically read and certify your component data.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildFeatureList(),
          if (_showFindDealer) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Don\'t have a module yet?',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: open dealer locator URL from server config
              },
              icon: const Icon(Icons.store_outlined, size: 18),
              label: const Text('Find a dealer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    const features = [
      (Icons.verified_outlined, 'Certified component data', 'Automatically reads motor, controller & battery info'),
      (Icons.track_changes_outlined, 'Live ride tracking', 'Real-time data from your motor system'),
      (Icons.history_outlined, 'Upgrade history', 'Complete log of every change to your bike'),
    ];
    return Column(
      children: features
          .map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(f.$1, size: 20, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(f.$3, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildButtons(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => _onYes(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth, size: 18),
                    SizedBox(width: 8),
                    Text('Yes, I have one', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => _onNo(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('No, I don\'t have one',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onYes(BuildContext context) async {
    // Force universal_ble to lazily instantiate CBCentralManager (iOS) /
    // BluetoothAdapter (Android) right here, so the system Bluetooth
    // permission prompt fires on this page rather than only after the
    // scanning page mounts. Without this, the prompt can be delayed/
    // skipped and the toggle never appears under Settings → TRAX.
    try {
      await UniversalBle.getBluetoothAvailabilityState();
    } catch (_) {
      // Non-fatal: AvailableDevicesPage will re-check and surface UI.
    }
    if (!context.mounted) return;
    final tracker = await Navigator.of(context).push<TrackerResult>(
      MaterialPageRoute(builder: (_) => const AvailableDevicesPage()),
    );
    if (tracker == null || !context.mounted) return;
    final bike = await Navigator.of(context).push<EBike>(
      MaterialPageRoute(builder: (_) => EbikePartsPage(trackerResult: tracker)),
    );
    if (bike != null && context.mounted) Navigator.of(context).pop(bike);
  }

  Future<void> _onNo(BuildContext context) async {
    final bike = await Navigator.of(context).push<EBike>(
      MaterialPageRoute(builder: (_) => const EbikePartsPage(showTraxOption: false)),
    );
    if (bike != null && context.mounted) Navigator.of(context).pop(bike);
  }
}
