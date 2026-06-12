import 'package:flutter/material.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/app_restart.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../models/ebike.dart';
import '../../models/ebike_model_data.dart';
import '../../theme/app_theme.dart';
import 'ebike_parts_page.dart';
import 'module_detail_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class EbikeProfilePage extends StatefulWidget {
  final EBike bike;
  const EbikeProfilePage({super.key, required this.bike});

  @override
  State<EbikeProfilePage> createState() => _EbikeProfilePageState();
}

class _EbikeProfilePageState extends State<EbikeProfilePage> {
  late EBike _bike;

  @override
  void initState() {
    super.initState();
    _bike = widget.bike;
  }

  Future<void> _goToEdit() async {
    final updated = await Navigator.of(context).push<EBike>(
      MaterialPageRoute(builder: (_) => EbikePartsPage(existingBike: _bike)),
    );
    if (updated != null) setState(() => _bike = updated);
  }

  void _confirmDelete() {
    TraxDialog.showBottomTipsDialog(
      title: 'Remove bike',
      content: 'Remove "${_bike.name}" from your garage?',
      mainBtnText: 'Remove',
      mainBtnOnPressed: () async {
        Navigator.of(context).pop(); // dismiss dialog
        final resp = await TraxApi.deleteBike(_bike.id.toString());
        if (!mounted) return;
        if (resp.isSuccess()) {
          Navigator.of(context).pop((null, true)); // (updated, deleted)
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to remove bike', isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '203', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _bike != widget.bike) {
          // pop was already handled; nothing to do here since we already popped
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildConnectionStatus(),
                  const SizedBox(height: 20),
                  _buildSpecsCard(),
                  const SizedBox(height: 20),
                  _buildStatsCard(),
                  const SizedBox(height: 20),
                  _buildActionsCard(),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.of(context).pop((_bike != widget.bike ? _bike : null, false)),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
          onPressed: AppRestart.restart,
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Colors.white),
          onPressed: _goToEdit,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.electric_bike, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(_bike.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              if (_bike.modelData != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_bike.modelData!.brand} ${_bike.modelData!.model}',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final connected = _bike.traxSerialNumber != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? AppColors.success.withValues(alpha: 0.4) : AppColors.divider,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'TRA-X connected' : 'No TRA-X module',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: connected ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
                if (connected)
                  Text('SN: ${_bike.traxSerialNumber}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsCard() {
    return _SectionCard(
      title: 'Specs',
      child: Column(
        children: [
          if (_bike.modelData != null) ...[
            _SpecRow(
                label: 'Model',
                value: '${_bike.modelData!.brand} ${_bike.modelData!.model}',
                icon: Icons.electric_bike_outlined),
            const Divider(height: 1, color: AppColors.divider),
          ],
          if (_bike.motor.isNotEmpty) ...[
            _SpecRow(
                label: 'Motor',
                value: _bike.motor,
                icon: Icons.bolt_outlined,
                certified: _bike.motorCertified),
            const Divider(height: 1, color: AppColors.divider),
          ],
          if (_bike.controller.isNotEmpty) ...[
            _SpecRow(
                label: 'Controller',
                value: _bike.controller,
                icon: Icons.memory_outlined,
                certified: _bike.controllerCertified),
            const Divider(height: 1, color: AppColors.divider),
          ],
          if (_bike.battery.isNotEmpty)
            _SpecRow(
                label: 'Battery',
                value: _bike.battery,
                icon: Icons.battery_charging_full_outlined,
                certified: _bike.batteryCertified),
          if (_bike.modelData == null && _bike.motor.isEmpty && _bike.controller.isEmpty && _bike.battery.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No specs added yet',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return _SectionCard(
      title: 'Statistics',
      child: Row(
        children: [
          Expanded(child: _StatBox(label: 'Total Rides', value: '0')),
          Container(width: 1, height: 48, color: AppColors.divider),
          Expanded(child: _StatBox(label: 'Total Distance', value: '0 km')),
          Container(width: 1, height: 48, color: AppColors.divider),
          Expanded(child: _StatBox(label: 'Last Ride', value: '—')),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    final hasModule = _bike.traxSerialNumber != null && _bike.traxSerialNumber!.isNotEmpty;
    return _SectionCard(
      title: 'Actions',
      child: Column(
        children: [
          _ActionRow(icon: Icons.history, label: 'View ride history', onTap: () {}),
          const Divider(height: 1, color: AppColors.divider),
          _ActionRow(icon: Icons.settings_outlined, label: 'Motor settings', onTap: () {}),
          if (hasModule) ...[
            const Divider(height: 1, color: AppColors.divider),
            _ActionRow(
              icon: Icons.analytics_outlined,
              label: 'Show module detail',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ModuleDetailPage(
                      serialNo: _bike.traxSerialNumber!,
                      bikeName: _bike.name,
                    ),
                  ),
                );
              },
            ),
          ],
          const Divider(height: 1, color: AppColors.divider),
          _ActionRow(
              icon: Icons.delete_outline,
              label: 'Remove this bike',
              color: AppColors.error,
              onTap: _confirmDelete),
        ],
      ),
    );
  }
}

// ─── Reusable sub-widgets ────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 1.2)),
        ),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool certified;
  const _SpecRow({required this.label, required this.value, required this.icon, this.certified = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          // Left: Icon + Label (minimum width)
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Right: Value + Certified Icon
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (certified) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.verified, size: 18, color: AppColors.success),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.label, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c))),
            Icon(Icons.chevron_right, size: 18,
                color: color != null ? color!.withValues(alpha: 0.5) : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
