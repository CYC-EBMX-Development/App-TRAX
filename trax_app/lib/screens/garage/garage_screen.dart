import 'package:flutter/material.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../theme/app_theme.dart';
import 'ebike_profile_page.dart';
import 'trax_module_inquiry_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  late List<EBike> _bikes = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBikes();
  }

  Future<void> _loadBikes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final response = await TraxApi.getUserBikes();
    if (!mounted) return;

    if (response.isSuccess() && response.data != null) {
      final bikes = <EBike>[];
      for (final item in response.data as List) {
        bikes.add(EBike.fromJson(item as Map<String, dynamic>));
      }
      setState(() {
        _bikes = bikes;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = response.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _goToAddBike() async {
    final result = await Navigator.of(context).push<EBike>(
      MaterialPageRoute(builder: (_) => const TraxModuleInquiryPage()),
    );
    if (result != null) setState(() => _bikes.add(result));
  }

  Future<void> _goToProfile(int index) async {
    final bike = _bikes[index];
    // Returns (EBike? updated, bool deleted)
    final result = await Navigator.of(context).push<(EBike?, bool)>(
      MaterialPageRoute(builder: (_) => EbikeProfilePage(bike: bike)),
    );
    if (result == null) return;
    final (updated, deleted) = result;
    setState(() {
      if (deleted) {
        _bikes.removeAt(index);
      } else if (updated != null) {
        _bikes[index] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '200', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Garage'),
        actions: [
          if (_bikes.isNotEmpty)
            IconButton(icon: const Icon(Icons.add), onPressed: _goToAddBike),
          if (!_isLoading)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadBikes),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _bikes.isEmpty
                  ? _buildEmptyState()
                  : _buildBikeList(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            'Failed to load bikes',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _loadBikes,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: GestureDetector(
        onTap: _goToAddBike,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Icon(Icons.add, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('Add a new bike', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Tap to register your eBike', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildBikeList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _bikes.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _BikeCard(bike: _bikes[index], onTap: () => _goToProfile(index)),
      ),
    );
  }
}

// ─── Bike Card ───────────────────────────────────────────────────

class _BikeCard extends StatelessWidget {
  final EBike bike;
  final VoidCallback onTap;
  const _BikeCard({required this.bike, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BikeCardHeader(bike: bike),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bike.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _ConnectionBadge(connected: bike.traxSerialNumber != null),
                    ],
                  ),
                  if (bike.modelData != null || bike.motor.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _SpecsRow(bike: bike),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BikeCardHeader extends StatelessWidget {
  final EBike bike;
  const _BikeCardHeader({required this.bike});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        height: 156,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: bike.imageUrl != null
              ? Image.network(bike.imageUrl!, height: 120, fit: BoxFit.contain)
              : Icon(Icons.electric_bike, size: 72, color: AppColors.primary.withValues(alpha: 0.9)),
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final bool connected;
  const _ConnectionBadge({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? AppColors.success : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          connected ? 'TRA-X' : 'No module',
          style: TextStyle(
            fontSize: 12,
            color: connected ? AppColors.success : AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SpecsRow extends StatelessWidget {
  final EBike bike;
  const _SpecsRow({required this.bike});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (bike.modelData != null) {
      chips.add(_SpecChip(
        icon: Icons.electric_bike_outlined,
        label: bike.modelData!.model,
      ));
    }
    if (bike.motor.isNotEmpty) {
      chips.add(_SpecChip(
        icon: Icons.bolt,
        label: bike.motor,
        certified: bike.motorCertified,
      ));
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _SpecChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool certified;
  const _SpecChip({required this.icon, required this.label, this.certified = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: certified ? AppColors.success.withValues(alpha: 0.08) : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: certified ? Border.all(color: AppColors.success.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (certified) ...[
            const Text('✅', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
          ] else ...[
            Icon(icon, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
