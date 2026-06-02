import 'package:flutter/material.dart';

import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

/// Two-step Change Password wizard.
///
/// Step 1 (verify):  user types the **current** password and taps
///                   Continue. The server validates it; on success
///                   we advance to step 2.  No new-password fields
///                   are shown until then.
/// Step 2 (update):  new password + confirm new password. Submit
///                   calls `PUT /users/me/password` with the verified
///                   current password.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

enum _Step { verify, update }

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  // Step 1
  final _verifyFormKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  bool _obscureCurrent = true;
  bool _verifying = false;

  // Step 2
  final _updateFormKey = GlobalKey<FormState>();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  _Step _step = _Step.verify;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyCurrent() async {
    if (_verifying) return;
    if (!(_verifyFormKey.currentState?.validate() ?? false)) return;
    setState(() => _verifying = true);
    final resp = await TraxApi.verifyPassword(password: _currentController.text);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (resp.isSuccess()) {
      setState(() => _step = _Step.update);
    } else {
      showTraxSnackBar(
        context,
        resp.message.isEmpty ? 'Current password is incorrect' : resp.message,
      );
    }
  }

  Future<void> _submitNew() async {
    if (_saving) return;
    if (!(_updateFormKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final resp = await TraxApi.changePassword(
      oldPassword: _currentController.text,
      newPassword: _newController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Password changed successfully');
      Navigator.of(context).pop();
    } else {
      showTraxSnackBar(
        context,
        resp.message.isEmpty ? 'Failed to change password' : resp.message,
      );
    }
  }

  String? _validateCurrent(String? v) {
    if (v == null || v.isEmpty) return 'Current password is required';
    return null;
  }

  String? _validateNew(String? v) {
    if (v == null || v.isEmpty) return 'New password is required';
    if (v.length < 6) return 'At least 6 characters';
    if (v == _currentController.text) {
      return 'New password must differ from current';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm the new password';
    if (v != _newController.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '302', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Change Password')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: _step == _Step.verify ? _buildVerifyStep() : _buildUpdateStep(),
      ),
    );
  }

  Widget _buildVerifyStep() {
    return Form(
      key: _verifyFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your current password to continue.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          _label('Current Password'),
          _HidingHintPasswordField(
            controller: _currentController,
            hint: 'Enter your current password',
            obscure: _obscureCurrent,
            onToggleObscure: () =>
                setState(() => _obscureCurrent = !_obscureCurrent),
            validator: _validateCurrent,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onFieldSubmitted: (_) => _verifyCurrent(),
          ),
          const SizedBox(height: 28),
          _primaryButton(
            label: 'Continue',
            busy: _verifying,
            onPressed: _verifyCurrent,
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateStep() {
    return Form(
      key: _updateFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.check_circle, color: AppColors.success, size: 18),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Current password verified. Set your new password.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label('New Password'),
          _HidingHintPasswordField(
            controller: _newController,
            hint: 'At least 6 characters',
            obscure: _obscureNew,
            onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
            validator: _validateNew,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          _label('Confirm New Password'),
          _HidingHintPasswordField(
            controller: _confirmController,
            hint: 'Re-enter the new password',
            obscure: _obscureConfirm,
            onToggleObscure: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
            validator: _validateConfirm,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitNew(),
          ),
          const SizedBox(height: 28),
          _primaryButton(
            label: 'Update Password',
            busy: _saving,
            onPressed: _submitNew,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      setState(() {
                        _step = _Step.verify;
                        _newController.clear();
                        _confirmController.clear();
                      });
                    },
              child: const Text('Re-verify current password'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _primaryButton({
    required String label,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Password input that:
///   * uses a medium-gray hint (never black) so the placeholder is
///     visibly distinct from real input
///   * hides the hint while the field has keyboard focus
///   * toggles obscure-text via a trailing visibility icon
class _HidingHintPasswordField extends StatefulWidget {
  const _HidingHintPasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggleObscure,
    required this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? Function(String?) validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;

  @override
  State<_HidingHintPasswordField> createState() =>
      _HidingHintPasswordFieldState();
}

class _HidingHintPasswordFieldState extends State<_HidingHintPasswordField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      obscureText: widget.obscure,
      autocorrect: false,
      enableSuggestions: false,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        hintText: _focusNode.hasFocus ? null : widget.hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(
              widget.obscure ? Icons.visibility_off : Icons.visibility,
              color: AppColors.textSecondary),
          onPressed: widget.onToggleObscure,
        ),
      ),
    );
  }
}
