import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../../common/network/app_response.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/model_image_card.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/bike_brand.dart';
import '../../models/bike_model.dart';
import '../../models/ebike_model_data.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ModelPickerPage extends StatefulWidget {
  final EBikeModelData? initial;
  const ModelPickerPage({super.key, this.initial});

  @override
  State<ModelPickerPage> createState() => _ModelPickerPageState();
}

class _ModelPickerPageState extends State<ModelPickerPage> {
  List<BikeBrand> _brands = [];
  List<BikeModel> _models = [];
  BikeBrand? _selectedBrand;
  BikeModel? _selectedModel;
  bool _brandsLoading = true;
  bool _modelsLoading = false;
  String? _brandsError;
  String? _modelsError;

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _initializeSelection();
  }

  Future<void> _initializeSelection() async {
    if (widget.initial == null) return;

    // Wait briefly for brands to load
    await Future.delayed(const Duration(milliseconds: 300));

    final targetBrandName = widget.initial!.brand;
    final targetModelName = widget.initial!.model;

    // Find and select the brand
    final matchingBrand =
        _brands.firstWhereOrNull((b) => b.name == targetBrandName);
    if (matchingBrand != null) {
      setState(() => _selectedBrand = matchingBrand);
      await _loadModels(matchingBrand);

      // Find and select the model
      final matchingModel =
          _models.firstWhereOrNull((m) => m.modelName == targetModelName);
      if (matchingModel != null) {
        setState(() => _selectedModel = matchingModel);
      }
    }
  }

  Future<void> _loadBrands() async {
    setState(() => _brandsLoading = true);
    try {
      final response = await TraxApi.getBrands();
      if (response.flag) {
        final brands = (response.data as List)
            .map((item) => BikeBrand.fromJson(item as Map<String, dynamic>))
            .toList();
        setState(() {
          _brands = brands;
          _brandsError = null;
        });
      } else {
        setState(() => _brandsError = response.message);
      }
    } catch (e) {
      setState(() => _brandsError = 'Failed to load brands: $e');
    } finally {
      setState(() => _brandsLoading = false);
    }
  }

  Future<void> _loadModels(BikeBrand brand) async {
    setState(() => _modelsLoading = true);
    try {
      final response = await TraxApi.getModelsByBrand(brand.id);
      if (response.flag) {
        final models = (response.data as List)
            .map((item) => BikeModel.fromJson(item as Map<String, dynamic>))
            .toList();
        setState(() {
          _models = models;
          _modelsError = null;
        });
      } else {
        setState(() => _modelsError = response.message);
      }
    } catch (e) {
      setState(() => _modelsError = 'Failed to load models: $e');
    } finally {
      setState(() => _modelsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '202', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Select Model'),
      ),
      body: Column(
        children: [
          // Top section: Brands and Models list
          Expanded(
            flex: 1,
            child: Row(
              children: [
                // Brand column
                SizedBox(
                  width: 120,
                  child: Container(
                    color: AppColors.surface,
                    child: _brandsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _brandsError != null
                            ? Center(
                                child: Text(
                                  _brandsError!,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: _brands.length,
                                itemBuilder: (context, i) {
                                  final brand = _brands[i];
                                  final isSelected = brand.id == _selectedBrand?.id;
                                  return _BrandTile(
                                    brand: brand,
                                    isSelected: isSelected,
                                    onTap: () async {
                                      setState(() {
                                        _selectedBrand = brand;
                                        _selectedModel = null;
                                      });
                                      await _loadModels(brand);
                                    },
                                  );
                                },
                              ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // Model column
                Expanded(
                  child: Container(
                    color: AppColors.surface,
                    child: _modelsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _modelsError != null
                            ? Center(
                                child: Text(
                                  _modelsError!,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _models.isEmpty
                                ? Center(
                                    child: Text(
                                      _selectedBrand == null
                                          ? 'Select a brand'
                                          : 'No models',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _models.length,
                                    itemBuilder: (context, i) {
                                      final model = _models[i];
                                      final isSelected = model.id == _selectedModel?.id;
                                      return _ModelTile(
                                        model: model,
                                        isSelected: isSelected,
                                        onTap: () => setState(() => _selectedModel = model),
                                      );
                                    },
                                  ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Bottom section: Image and Specs side by side
          if (_selectedModel != null)
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  // Left: Image area
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ModelImageCard(
                        imageUrl: _selectedModel!.imageUrl,
                        modelName: _selectedModel!.modelName,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  // Right: Specs area
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedModel!.modelName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSpecRow(
                            'Brand',
                            _selectedModel!.brandName,
                          ),
                          if (_selectedModel!.motorType != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow('Motor', _selectedModel!.motorType!),
                          ],
                          if (_selectedModel!.motorPeakPowerW != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow(
                              'Power',
                              '${_selectedModel!.motorPeakPowerW} W',
                            ),
                          ],
                          if (_selectedModel!.motorTorqueNm != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow(
                              'Torque',
                              '${_selectedModel!.motorTorqueNm} Nm',
                            ),
                          ],
                          if (_selectedModel!.controller != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow('Controller', _selectedModel!.controller!),
                          ],
                          if (_selectedModel!.batteryType != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow('Battery', _selectedModel!.batteryType!),
                          ],
                          if (_selectedModel!.batteryVoltage != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow('Voltage', _selectedModel!.batteryVoltage!),
                          ],
                          if (_selectedModel!.batteryCapacityWh != null) ...[
                            const SizedBox(height: 12),
                            _buildSpecRow(
                              'Capacity',
                              '${_selectedModel!.batteryCapacityWh} Wh',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              flex: 1,
              child: Center(
                child: Text(
                  'Select a model to view details',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedModel != null
                          ? () {
                              final ebike = EBikeModelData.fromBikeModel(_selectedModel!);
                              Navigator.of(context).pop(ebike);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.divider,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BrandTile extends StatelessWidget {
  final BikeBrand brand;
  final bool isSelected;
  final VoidCallback onTap;
  const _BrandTile({required this.brand, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
          color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : null,
        ),
        child: Text(
          brand.name,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final BikeModel model;
  final bool isSelected;
  final VoidCallback onTap;
  const _ModelTile({required this.model, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.modelName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
          ],
        ),
      ),
    );
  }
}
