import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../common/services/map_service.dart';
import '../theme/app_theme.dart';

/// Floating search box for the map. Shows an input field; on submit (or
/// after a short debounce while typing) calls [MapService.searchPlaces]
/// and renders a dropdown of results. Tapping a result invokes
/// [onPick] with the WGS-84 location of the selected place.
class MapSearchBox extends StatefulWidget {
  final LatLng? near;
  final ValueChanged<PlaceResult> onPick;
  final EdgeInsetsGeometry margin;

  const MapSearchBox({
    super.key,
    required this.onPick,
    this.near,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 0),
  });

  @override
  State<MapSearchBox> createState() => _MapSearchBoxState();
}

class _MapSearchBoxState extends State<MapSearchBox> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _busy = false;
  bool _expanded = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = const [];
        _expanded = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(v));
  }

  Future<void> _runSearch(String v) async {
    if (!mounted) return;
    setState(() => _busy = true);
    final res = await MapService.searchPlaces(v, near: widget.near);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = res;
      _expanded = res.isNotEmpty;
    });
  }

  void _pick(PlaceResult r) {
    _focus.unfocus();
    setState(() {
      _expanded = false;
      _ctrl.text = r.name;
    });
    widget.onPick(r);
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _results = const [];
      _expanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(28),
            color: AppColors.surface,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _runSearch(v);
              },
              decoration: InputDecoration(
                hintText: 'Search address or place',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
                prefixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : const Icon(Icons.search,
                        color: AppColors.textSecondary, size: 20),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary, size: 18),
                        onPressed: _clear,
                      ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_expanded && _results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: AppColors.textSecondary.withValues(alpha: 0.12),
                ),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return InkWell(
                    onTap: () => _pick(r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (r.address.isNotEmpty &&
                                    r.address != r.name) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    r.address,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
