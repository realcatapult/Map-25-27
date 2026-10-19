import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/services/auth_service.dart';
import 'package:login_ui/services/theme_service.dart';
import 'package:login_ui/components/interests_picker_dialog.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'package:login_ui/services/profile_cache.dart';
import 'package:login_ui/components/skeleton_loader.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'my_check_in_code_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  String? _profilePictureUrl;
  List<String> _interests = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final profilePic = await _chatService.getProfilePicture(
        currentUser.email!,
      );
      final userData = await _chatService.getUserData(currentUser.email!);

      setState(() {
        _profilePictureUrl = profilePic;
        _firstNameController.text = userData?['firstName'] ?? '';
        _lastNameController.text = userData?['lastName'] ?? '';
        _bioController.text = userData?['bio'] ?? '';
        _interests = List<String>.from(
          userData?['interests'] ?? const <String>[],
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _editInterests() async {
    final selected = await showInterestsPickerDialog(
      context,
      initialSelection: _interests,
    );

    if (selected == null || selected.isEmpty) return;
    final chosen = selected;

    setState(() {
      _isSaving = true;
    });

    try {
      await _chatService.updateCurrentUserInterests(chosen);

      if (!mounted) return;
      setState(() {
        _interests = chosen;
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Interests updated!')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating interests: $e')));
    }
  }

  Future<void> _pickAndUploadProfilePicture() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isSaving = true;
      });

      final imageUrl = await _chatService.uploadProfilePicture(
        File(image.path),
      );
      await _chatService.updateProfilePicture(imageUrl);

      setState(() {
        _profilePictureUrl = imageUrl;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile picture: $e')),
        );
      }
    }
  }

  Future<void> _saveUserData() async {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both first and last name')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _chatService.updateUserData(
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
      );
      await _chatService.updateCurrentUserBio(_bioController.text);
      // Drop the cached copy so chat headers and profile cards pick up the
      // new name and bio instead of serving what they loaded earlier.
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email != null) ProfileCache.instance.invalidate(email);

      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated!')));
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: NeonBackground(
        child: _isLoading
            ? const SkeletonList()
            : _buildProfile(context, currentUser),
      ),
    );
  }

  // ── Instagram-style profile ──────────────────────────────────────────────

  String get _displayName {
    final f = _firstNameController.text.trim();
    final l = _lastNameController.text.trim();
    final name = [f, l].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? 'Your Name' : name;
  }

  Widget _buildProfile(BuildContext context, User? currentUser) {
    final cs = Theme.of(context).colorScheme;
    final handle = (currentUser?.email ?? '').split('@').first;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 20),
        // Header: avatar + stats row (IG style)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              GestureDetector(
                onTap: _isSaving ? null : _pickAndUploadProfilePicture,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: cs.surfaceContainerHighest,
                      backgroundImage: _profilePictureUrl != null
                          ? NetworkImage(_profilePictureUrl!)
                          : null,
                      child: _profilePictureUrl == null
                          ? Icon(
                              Icons.person,
                              size: 44,
                              color: cs.onSurfaceVariant,
                            )
                          : null,
                    ),
                    if (_isSaving)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.brass,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: AppColors.navy,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(context, _interests.length.toString(), 'Interests'),
                    _stat(context, 'Member', 'Status'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Name + handle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              if (handle.isNotEmpty)
                Text(
                  '@$handle',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Edit profile + Edit interests buttons (IG-style pair)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: _profileButton(
                  context,
                  label: 'Edit Profile',
                  onTap: _isSaving ? null : _openEditProfileSheet,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _profileButton(
                  context,
                  label: 'Edit Interests',
                  onTap: _isSaving ? null : _editInterests,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Interests "highlights" row
        if (_interests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _interests
                  .map(
                    (i) => Chip(
                      label: Text(i),
                      backgroundColor: AppColors.brass.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: AppColors.brass.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 8),
        Divider(color: cs.outlineVariant.withValues(alpha: 0.4), height: 32),
        // Settings list (IG-style rows)
        _settingsRow(
          context,
          icon: Icons.dark_mode_outlined,
          label: 'Dark Mode',
          trailing: Switch(
            value: ThemeService.isDark,
            onChanged: (v) =>
                ThemeService.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
        ),
        _settingsRow(
          context,
          icon: Icons.email_outlined,
          label: 'Email',
          subtitle: currentUser?.email ?? '',
        ),
        _settingsRow(
          context,
          icon: Icons.qr_code_2,
          label: 'My Check-In Code',
          subtitle: 'Show this to a club admin at events',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCheckInCodePage()),
          ),
        ),
        _settingsRow(
          context,
          icon: Icons.logout,
          label: 'Sign Out',
          danger: true,
          onTap: _isSaving ? null : _signOut,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _profileButton(
    BuildContext context, {
    required String label,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _settingsRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? Colors.red : cs.onSurface;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: danger ? Colors.red : cs.onSurfaceVariant),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant))
          : null,
      trailing:
          trailing ??
          (onTap != null && !danger
              ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
              : null),
    );
  }

  /// IG-style "Edit Profile" bottom sheet for name fields.
  Future<void> _openEditProfileSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Edit Profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'First Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Last Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                maxLines: 3,
                minLines: 2,
                maxLength: 190,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'A line or two about you',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          await _saveUserData();
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          setState(() {}); // refresh displayed name
                        },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }
}
