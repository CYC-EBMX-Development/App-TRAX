import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../common/global/global_user_info.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  String _avatarUrl = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final info = GlobalUserInfo.instance;
    _nameController.text = info.name.value;
    _avatarUrl = info.avatar.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop();
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (picked == null) return;
      await _uploadAvatar(File(picked.path));
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to pick image: $e');
    }
  }

  Future<void> _uploadAvatar(File file) async {
    final resp = await TraxApi.uploadAvatar(file.path);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is Map) {
      final m = resp.data as Map<String, dynamic>;
      final newUrl = (m['avatarUrl'] as String?) ?? '';
      setState(() => _avatarUrl = newUrl);
      _applyToGlobal(m);
      _showSnack('Avatar updated');
    } else {
      _showSnack(resp.message.isEmpty ? 'Avatar upload failed' : resp.message);
    }
  }

  void _showAvatarSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: const Text('Take a photo'),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _showSnack('Name cannot be empty');
      return;
    }
    if (newName == GlobalUserInfo.instance.name.value) {
      Get.back();
      return;
    }
    setState(() => _saving = true);
    final resp = await TraxApi.updateProfile(username: newName);
    if (!mounted) return;
    setState(() => _saving = false);
    if (resp.isSuccess() && resp.data is Map) {
      _applyToGlobal(resp.data as Map<String, dynamic>);
      _showSnack('Profile saved');
      Get.back();
    } else {
      _showSnack(resp.message.isEmpty ? 'Save failed' : resp.message);
    }
  }

  void _applyToGlobal(Map<String, dynamic> m) {
    final info = GlobalUserInfo.instance;
    info.setUserInfo(
      id: (m['id'] as num?)?.toInt() ?? info.id.value,
      name: (m['username'] as String?) ?? info.name.value,
      email: (m['email'] as String?) ?? info.email.value,
      avatar: (m['avatarUrl'] as String?) ?? info.avatar.value,
    );
    // Persist to local storage for app restart restore.
    TraxStorageUtil.saveUserInfo(
      '{"avatarUrl":"${m['avatarUrl'] ?? ''}",'
      '"id":${m['id'] ?? 'null'},'
      '"email":"${m['email'] ?? ''}",'
      '"username":"${m['username'] ?? ''}"}',
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '301', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final email = GlobalUserInfo.instance.email.value;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveName,
            child: Text('Save',
                style: TextStyle(
                  color: _saving ? AppColors.textSecondary : AppColors.primary,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(child: _buildAvatar()),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _showAvatarSheet,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Change Photo'),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Name',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Your display name',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              maxLength: 32,
            ),
            const SizedBox(height: 8),
            const Text('Email',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              enabled: false,
              controller: TextEditingController(text: email),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Email cannot be changed.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final hasUrl = _avatarUrl.isNotEmpty &&
        Uri.tryParse(_avatarUrl)?.hasScheme == true;
    final letter = _nameController.text.isNotEmpty
        ? _nameController.text[0].toUpperCase()
        : 'T';
    return GestureDetector(
      onTap: _showAvatarSheet,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: AppColors.primary,
            backgroundImage: hasUrl ? NetworkImage(_avatarUrl) : null,
            child: !hasUrl
                ? Text(letter,
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                : null,
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt,
                color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}
