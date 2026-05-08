import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/global/global_user_info.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../models/ebike_history.dart';
import '../../models/ebike_model_data.dart';
import '../../models/tracker_result.dart';
import '../../theme/app_theme.dart';
import 'available_devices_page.dart';
import 'model_picker_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class EbikePartsPage extends StatefulWidget {
  final EBike? existingBike;
  final TrackerResult? trackerResult;
  final bool showTraxOption;

  const EbikePartsPage({
    super.key,
    this.existingBike,
    this.trackerResult,
    this.showTraxOption = true,
  });

  @override
  State<EbikePartsPage> createState() => _EbikePartsPageState();
}

class _EbikePartsPageState extends State<EbikePartsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _motorCtrl = TextEditingController();
  final _controllerCtrl = TextEditingController();
  final _batteryCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();

  String? _traxSerial;
  EBikeModelData? _selectedModel;
  EBikeType? _type;
  bool _motorCertified = false;
  bool _controllerCertified = false;
  bool _batteryCertified = false;

  // Track certified values — editing these removes the certified badge
  String _certMotorVal = '';
  String _certControllerVal = '';
  String _certBatteryVal = '';

  bool get _isUpgrade => widget.existingBike != null;

  @override
  void initState() {
    super.initState();
    _loadExistingBike();
    _applyTracker();
    _motorCtrl.addListener(_checkMotorCert);
    _controllerCtrl.addListener(_checkControllerCert);
    _batteryCtrl.addListener(_checkBatteryCert);
  }

  void _loadExistingBike() {
    final bike = widget.existingBike;
    if (bike == null) {
      final username = GlobalUserInfo.instance.name.value;
      _nameCtrl.text = username.isNotEmpty ? "${username}'s bike" : 'My bike';
    } else {
      _nameCtrl.text = bike.name;
      _motorCtrl.text = bike.motor;
      _controllerCtrl.text = bike.controller;
      _batteryCtrl.text = bike.battery;
      _otherCtrl.text = bike.other ?? '';
      _traxSerial = bike.traxSerialNumber;
      _selectedModel = bike.modelData;
      _type = bike.type;
      _motorCertified = bike.motorCertified;
      _controllerCertified = bike.controllerCertified;
      _batteryCertified = bike.batteryCertified;
      _certMotorVal = bike.motor;
      _certControllerVal = bike.controller;
      _certBatteryVal = bike.battery;
    }
  }

  void _applyTracker() {
    final tracker = widget.trackerResult;
    if (tracker == null) return;

    _traxSerial = tracker.serialNumber;

    // Auto-fill model data if available
    if (tracker.hasModelData) {
      // Try to construct EBikeModelData (assuming eBike type for API models)
      _selectedModel = EBikeModelData(
        brand: tracker.modelBrand!,
        model: tracker.modelName!,
        type: EBikeType.eBike,
        defaultMotor: tracker.motor,
        defaultController: tracker.controller,
        defaultBattery: tracker.battery,
      );
      _type = _selectedModel!.type;
    }

    // Collect conflicts: field name → (existingValue, trackerValue)
    final conflicts = <String, (String, String)>{};

    void check(String field, TextEditingController ctrl, String? trackerVal) {
      if (trackerVal == null || trackerVal.isEmpty) return;
      if (ctrl.text.isNotEmpty && ctrl.text != trackerVal) {
        conflicts[field] = (ctrl.text, trackerVal);
      }
    }

    check('Motor', _motorCtrl, tracker.motor);
    check('Controller', _controllerCtrl, tracker.controller);
    check('Battery', _batteryCtrl, tracker.battery);

    // Auto-fill empty fields
    void fillIfEmpty(TextEditingController ctrl, String? val, bool certified,
        Function(bool) setCert, Function(String) setCertVal) {
      if (val == null || val.isEmpty) return;
      if (ctrl.text.isEmpty) {
        ctrl.text = val;
        if (certified) {
          setCert(true);
          setCertVal(val);
        }
      }
    }

    fillIfEmpty(_motorCtrl, tracker.motor, tracker.motorCertified,
        (v) => _motorCertified = v, (v) => _certMotorVal = v);
    fillIfEmpty(_controllerCtrl, tracker.controller, tracker.controllerCertified,
        (v) => _controllerCertified = v, (v) => _certControllerVal = v);
    fillIfEmpty(_batteryCtrl, tracker.battery, tracker.batteryCertified,
        (v) => _batteryCertified = v, (v) => _certBatteryVal = v);

    if (conflicts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showOverwriteDialog(conflicts, tracker),
      );
    }
  }

  void _checkMotorCert() {
    if (_motorCertified && _motorCtrl.text != _certMotorVal) {
      setState(() => _motorCertified = false);
    }
  }

  void _checkControllerCert() {
    if (_controllerCertified && _controllerCtrl.text != _certControllerVal) {
      setState(() => _controllerCertified = false);
    }
  }

  void _checkBatteryCert() {
    if (_batteryCertified && _batteryCtrl.text != _certBatteryVal) {
      setState(() => _batteryCertified = false);
    }
  }

  void _showOverwriteDialog(Map<String, (String, String)> conflicts, TrackerResult tracker) {
    if (!mounted) return;
    final fieldList = conflicts.keys.join(', ');
    TraxDialog.showBottomTipsDialog(
      title: 'TRA-X module detected data',
      content: 'The module has data for: $fieldList.\nDo you want to replace your current entries?',
      mainBtnText: 'Replace',
      mainBtnOnPressed: () {
        Navigator.pop(context);
        setState(() {
          if (conflicts.containsKey('Motor') && tracker.motor != null) {
            _motorCtrl.text = tracker.motor!;
            _motorCertified = tracker.motorCertified;
            _certMotorVal = tracker.motor!;
          }
          if (conflicts.containsKey('Controller') && tracker.controller != null) {
            _controllerCtrl.text = tracker.controller!;
            _controllerCertified = tracker.controllerCertified;
            _certControllerVal = tracker.controller!;
          }
          if (conflicts.containsKey('Battery') && tracker.battery != null) {
            _batteryCtrl.text = tracker.battery!;
            _batteryCertified = tracker.batteryCertified;
            _certBatteryVal = tracker.battery!;
          }
        });
      },
      subBtnText: 'Keep mine',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _motorCtrl.dispose();
    _controllerCtrl.dispose();
    _batteryCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  // ─── Navigation ───────────────────────────────────────────────

  Future<void> _pickModel() async {
    final result = await Navigator.of(context).push<EBikeModelData>(
      MaterialPageRoute(builder: (_) => ModelPickerPage(initial: _selectedModel)),
    );
    if (result == null) return;
    setState(() {
      _selectedModel = result;
      _type = result.type;

      // Auto-fill or clear component fields based on model data
      // If model has the component, use it; if null, clear the field
      // Remove certification since these come from the model, not the module
      _motorCtrl.text = result.defaultMotor ?? '';
      _motorCertified = false;
      _certMotorVal = '';

      _controllerCtrl.text = result.defaultController ?? '';
      _controllerCertified = false;
      _certControllerVal = '';

      _batteryCtrl.text = result.defaultBattery ?? '';
      _batteryCertified = false;
      _certBatteryVal = '';
    });
  }

  Future<void> _connectTracker() async {
    final result = await Navigator.of(context).push<TrackerResult>(
      MaterialPageRoute(builder: (_) => const AvailableDevicesPage()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _traxSerial = result.serialNumber;

      // Auto-fill model if available
      if (result.hasModelData) {
        _selectedModel = EBikeModelData(
          brand: result.modelBrand!,
          model: result.modelName!,
          type: EBikeType.eBike,
          defaultMotor: result.motor,
          defaultController: result.controller,
          defaultBattery: result.battery,
        );
        _type = _selectedModel!.type;
      }
    });

    // Apply tracker data using the same conflict logic
    final conflicts = <String, (String, String)>{};
    void check(String f, TextEditingController c, String? v) {
      if (v == null || v.isEmpty) return;
      if (c.text.isNotEmpty && c.text != v) conflicts[f] = (c.text, v);
    }
    check('Motor', _motorCtrl, result.motor);
    check('Controller', _controllerCtrl, result.controller);
    check('Battery', _batteryCtrl, result.battery);

    void fillIfEmpty(TextEditingController ctrl, String? val, bool cert,
        Function(bool) setCert, Function(String) setCertVal) {
      if (val == null || val.isEmpty || ctrl.text.isNotEmpty) return;
      ctrl.text = val;
      if (cert) { setCert(true); setCertVal(val); }
    }
    fillIfEmpty(_motorCtrl, result.motor, result.motorCertified,
        (v) => setState(() { _motorCertified = v; }), (v) => _certMotorVal = v);
    fillIfEmpty(_controllerCtrl, result.controller, result.controllerCertified,
        (v) => setState(() { _controllerCertified = v; }), (v) => _certControllerVal = v);
    fillIfEmpty(_batteryCtrl, result.battery, result.batteryCertified,
        (v) => setState(() { _batteryCertified = v; }), (v) => _certBatteryVal = v);

    if (conflicts.isNotEmpty) _showOverwriteDialog(conflicts, result);
  }

  void _removeTracker() {
    TraxDialog.showBottomTipsDialog(
      title: 'Remove TRA-X module',
      content: 'Unbind TRA-X $_traxSerial from this bike?',
      mainBtnText: 'Remove',
      mainBtnOnPressed: () {
        Navigator.pop(context);
        setState(() => _traxSerial = null);
      },
      subBtnText: 'Cancel',
    );
  }

  // ─── Save / Cancel ───────────────────────────────────────────

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final id = widget.existingBike?.id ?? now.millisecondsSinceEpoch.toString();

    final bike = EBike(
      id: id,
      name: _nameCtrl.text.trim(),
      traxSerialNumber: _traxSerial,
      motor: _motorCtrl.text.trim(),
      controller: _controllerCtrl.text.trim(),
      battery: _batteryCtrl.text.trim(),
      motorCertified: _motorCertified,
      controllerCertified: _controllerCertified,
      batteryCertified: _batteryCertified,
      modelData: _selectedModel,
      type: _type,
      other: _otherCtrl.text.trim().isEmpty ? null : _otherCtrl.text.trim(),
      isConnected: _traxSerial != null,
      createdAt: widget.existingBike?.createdAt ?? now,
    );

    // Save to backend
    final isCreating = widget.existingBike == null;
    final response = isCreating
        ? await TraxApi.createBike(bike.toJson())
        : await TraxApi.updateBike(id, bike.toJson());

    if (!mounted) return;

    if (!response.isSuccess()) {
      TraxDialog.messageTopDialog(response.message, false);
      return;
    }

    // Use server-returned bike data (contains the real DB-assigned ID)
    final finalBike = (isCreating && response.data != null && response.data is Map<String, dynamic>)
        ? EBike.fromJson(response.data as Map<String, dynamic>)
        : bike;

    // Generate history record (stored locally for now)
    _generateHistory(finalBike);

    if (mounted) {
      Navigator.of(context).pop(finalBike);
    }
  }

  void _generateHistory(EBike updated) {
    final existing = widget.existingBike;
    final changes = <String, String>{};
    if (existing == null) {
      changes['name'] = updated.name;
      if (updated.modelData != null) changes['model'] = '${updated.modelData!.brand} ${updated.modelData!.model}';
      if (updated.motor.isNotEmpty) changes['motor'] = updated.motor;
    } else {
      if (existing.name != updated.name) changes['Name'] = updated.name;
      if (existing.motor != updated.motor) changes['Motor'] = updated.motor;
      if (existing.controller != updated.controller) changes['Controller'] = updated.controller;
      if (existing.battery != updated.battery) changes['Battery'] = updated.battery;
      if (existing.traxSerialNumber != updated.traxSerialNumber) {
        changes['TRA-X'] = updated.traxSerialNumber ?? '(removed)';
      }
    }
    // TODO: persist history to local storage or backend
    final _ = EBikeHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bikeId: updated.id,
      timestamp: DateTime.now(),
      type: existing == null ? HistoryType.added : HistoryType.upgraded,
      changes: changes,
    );
  }

  void _onCancel() {
    TraxDialog.showBottomTipsDialog(
      title: 'Discard changes?',
      content: 'Your changes will not be saved.',
      mainBtnText: 'Discard',
      mainBtnOnPressed: () {
        Navigator.pop(context);
        Navigator.pop(context);
      },
      subBtnText: 'Keep editing',
    );
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '204', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle(_isUpgrade ? 'Edit bike' : 'New Bike'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('BIKE INFO', [
                      _buildNameField(),
                      const SizedBox(height: 12),
                      _buildModelRow(),
                      // Type display removed
                    ]),
                    const SizedBox(height: 20),
                    // Type display removed - do not show type warning
                    if (widget.showTraxOption) ...[
                      _buildSection('TRA-X MODULE', [_buildTraxRow()]),
                      const SizedBox(height: 20),
                    ],
                    _buildSection('COMPONENTS', [
                      _buildComponentField(
                        label: 'Motor',
                        icon: Icons.bolt_outlined,
                        ctrl: _motorCtrl,
                        certified: _motorCertified,
                      ),
                      const SizedBox(height: 12),
                      _buildComponentField(
                        label: 'Controller',
                        icon: Icons.memory_outlined,
                        ctrl: _controllerCtrl,
                        certified: _controllerCertified,
                      ),
                      const SizedBox(height: 12),
                      _buildComponentField(
                        label: 'Battery',
                        icon: Icons.battery_charging_full_outlined,
                        ctrl: _batteryCtrl,
                        certified: _batteryCertified,
                      ),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('OTHER', [_buildOtherField()]),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textSecondary, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      maxLength: 50,
      inputFormatters: [LengthLimitingTextInputFormatter(50)],
      decoration: _inputDecoration('Name', Icons.badge_outlined),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
    );
  }

  Widget _buildModelRow() {
    return InkWell(
      onTap: _pickModel,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.electric_bike_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: _selectedModel == null
                  ? Text('Select model', style: TextStyle(color: AppColors.textSecondary, fontSize: 15))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_selectedModel!.brand} ${_selectedModel!.model}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text('Model', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildTraxRow() {
    if (_traxSerial != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.bluetooth_connected, size: 20, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TRA-X $_traxSerial',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Connected', style: TextStyle(fontSize: 11, color: AppColors.success)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.swap_horiz, size: 20, color: AppColors.primary),
              tooltip: 'Reconnect',
              onPressed: _connectTracker,
            ),
            IconButton(
              icon: Icon(Icons.link_off, size: 20, color: AppColors.error),
              tooltip: 'Remove',
              onPressed: _removeTracker,
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: _connectTracker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.bluetooth_searching, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No module connected — tap to connect',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentField({
    required String label,
    required IconData icon,
    required TextEditingController ctrl,
    required bool certified,
  }) {
    return TextFormField(
      controller: ctrl,
      enabled: true,
      readOnly: false,
      maxLength: 50,
      inputFormatters: [LengthLimitingTextInputFormatter(50)],
      decoration: InputDecoration(
        labelText: certified ? '✅ $label (Certified)' : label,
        labelStyle: TextStyle(
          color: certified ? AppColors.success : null,
          fontWeight: certified ? FontWeight.w600 : null,
        ),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        suffixIcon: certified ? Icon(Icons.verified, size: 16, color: AppColors.success) : null,
        filled: true,
        fillColor: certified ? AppColors.success.withValues(alpha: 0.08) : AppColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: certified ? AppColors.success.withValues(alpha: 0.5) : AppColors.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: certified ? AppColors.success.withValues(alpha: 0.5) : AppColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: certified ? AppColors.success : AppColors.primary, width: 1.5)),
        counterText: '',
        helperText: certified ? 'Edit to remove certification' : null,
        helperStyle: TextStyle(
          color: AppColors.success.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildOtherField() {
    return TextFormField(
      controller: _otherCtrl,
      maxLines: 5,
      decoration: InputDecoration(
        hintText: 'Notes, mods, accessories…',
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  Widget _buildBottomButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _onCancel,
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
                onPressed: _onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _isUpgrade ? 'Save' : 'Add',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
      counterText: '',
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
    );
  }
}
