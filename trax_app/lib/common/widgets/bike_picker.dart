import 'package:flutter/material.dart';
import '../network/trax_api.dart';
import '../../theme/app_theme.dart';

/// Shared bike picker components used in race-related screens.
///
/// `BikePickerTile` is an inline, tappable tile showing the currently selected
/// bike (or a placeholder) that opens a modal bottom sheet of the user's bikes.
class BikePickerTile extends StatefulWidget {
  /// Currently selected bicycle id (nullable = none selected).
  final int? selectedBikeId;

  /// Pre-loaded list of bikes. If null, the widget loads them itself.
  final List<Map<String, dynamic>>? bikes;

  /// Called when the user picks (or clears) a bike.
  final ValueChanged<int?> onSelected;

  /// Whether the user is allowed to clear the selection (set to "no bike").
  final bool allowNone;

  /// Optional override label.
  final String? label;

  const BikePickerTile({
    super.key,
    required this.onSelected,
    this.selectedBikeId,
    this.bikes,
    this.allowNone = true,
    this.label,
  });

  @override
  State<BikePickerTile> createState() => _BikePickerTileState();
}

class _BikePickerTileState extends State<BikePickerTile> {
  List<Map<String, dynamic>>? _bikes;

  @override
  void initState() {
    super.initState();
    _bikes = widget.bikes;
    if (_bikes == null) _load();
  }

  @override
  void didUpdateWidget(covariant BikePickerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent pages often fetch bikes asynchronously after first build.
    // Keep local cache in sync when a concrete list is provided later.
    if (!identical(oldWidget.bikes, widget.bikes)) {
      _bikes = widget.bikes;
      if (_bikes == null) {
        _load();
      }
    }
  }

  Future<void> _load() async {
    final resp = await TraxApi.getUserBikes();
    if (!mounted || !resp.isSuccess()) return;
    setState(() {
      _bikes = (resp.data as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bikes = _bikes ?? const [];
    final selected = bikes
        .where((b) => (b['id'] as num?)?.toInt() == widget.selectedBikeId)
        .firstOrNull;
    return InkWell(
      onTap: () => _showSheet(context, bikes),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.two_wheeler,
              size: 20,
              color: selected != null
                  ? AppColors.primary
                  : AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected != null
                      ? (selected['name'] as String? ?? 'My Bike')
                      : (widget.label ?? 'Select your bike'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      selected['modelBrand'],
                      selected['modelName'],
                    ].where((s) => s != null).join(' \u00b7 '),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 20, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  Future<void> _showSheet(
      BuildContext context, List<Map<String, dynamic>> bikes) async {
    await showBikePickerSheet(
      context,
      bikes: bikes,
      selectedBikeId: widget.selectedBikeId,
      allowNone: widget.allowNone,
      onSelected: widget.onSelected,
    );
  }
}

/// Show a modal bottom sheet listing all bikes; calls [onSelected] with the
/// chosen bike id (or null if the user cleared the selection).
Future<void> showBikePickerSheet(
  BuildContext context, {
  required ValueChanged<int?> onSelected,
  List<Map<String, dynamic>>? bikes,
  int? selectedBikeId,
  bool allowNone = true,
}) async {
  // Load bikes lazily if not provided.
  List<Map<String, dynamic>> resolved = bikes ?? const [];
  if (bikes == null) {
    final resp = await TraxApi.getUserBikes();
    if (resp.isSuccess()) {
      resolved = (resp.data as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
    }
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Select Bike',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            if (resolved.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No bikes found. Add a bike in Garage first.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ...resolved.map((bike) {
              final bikeId = (bike['id'] as num).toInt();
              final isSelected = bikeId == selectedBikeId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.background,
                  backgroundImage: bike['imageUrl'] != null
                      ? NetworkImage(bike['imageUrl'] as String)
                      : null,
                  child: bike['imageUrl'] == null
                      ? Icon(Icons.two_wheeler,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary)
                      : null,
                ),
                title: Text(bike['name'] as String? ?? 'Bike',
                    style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500)),
                subtitle: Text(
                  [bike['modelBrand'], bike['modelName']]
                      .where((s) => s != null)
                      .join(' \u00b7 '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onSelected(bikeId);
                },
              );
            }),
            if (allowNone && selectedBikeId != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.background,
                  child: Icon(Icons.close, color: AppColors.textSecondary),
                ),
                title: const Text('No bike',
                    style: TextStyle(color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onSelected(null);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
