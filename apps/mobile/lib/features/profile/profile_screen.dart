import 'dart:async';

import 'package:flutter/material.dart';

import 'profile_model.dart';
import 'profile_transport.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.transport, super.key});

  final ProfileTransport transport;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _status = TextEditingController();
  final _timezone = TextEditingController();
  final _avatarUrl = TextEditingController();

  UserProfile? _profile;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    _status.dispose();
    _timezone.dispose();
    _avatarUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await widget.transport.fetchProfile();
      if (!mounted) return;
      _applyProfile(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _applyProfile(UserProfile profile) {
    _displayName.text = profile.displayName;
    _username.text = profile.username;
    _bio.text = profile.bio ?? '';
    _status.text = profile.statusText ?? '';
    _timezone.text = profile.timezone;
    _avatarUrl.text = profile.avatarUrl ?? '';
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;

    final existing = _profile;
    if (existing == null) return;

    setState(() => _saving = true);
    try {
      final profile = await widget.transport.updateProfile(
        username: _username.text.trim() == existing.username
            ? null
            : _username.text.trim(),
        displayName: _displayName.text.trim() == existing.displayName
            ? null
            : _displayName.text.trim(),
        avatarUrl: _avatarUrl.text.trim() == (existing.avatarUrl ?? '')
            ? null
            : _avatarUrl.text.trim(),
        bio: _bio.text.trim() == (existing.bio ?? '') ? null : _bio.text.trim(),
        timezone: _timezone.text.trim() == existing.timezone
            ? null
            : _timezone.text.trim(),
        statusText: _status.text.trim() == (existing.statusText ?? '')
            ? null
            : _status.text.trim(),
      );
      if (!mounted) return;
      _applyProfile(profile);
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _profile == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 110),
            const Icon(Icons.cloud_off_rounded, size: 46, color: Colors.white38),
            const SizedBox(height: 16),
            const Text(
              'Could not load your profile',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final profile = _profile!;
    final avatarText = profile.displayName.trim().isNotEmpty
        ? profile.displayName.trim().characters.first.toUpperCase()
        : profile.username.trim().isNotEmpty
            ? profile.username.trim().characters.first.toUpperCase()
            : '?';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF153A39),
                child: Text(
                  avatarText,
                  style: const TextStyle(
                    color: Color(0xFF68E0CF),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${profile.username}',
                      style: const TextStyle(color: Color(0xFF68E0CF)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.email,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _displayName,
                  textInputAction: TextInputAction.next,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Display name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (value) {
                    final username = value?.trim() ?? '';
                    if (username.length < 3) {
                      return 'Use at least 3 characters';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(username)) {
                      return 'Use letters, numbers, dots, dashes, or underscores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _status,
                  textInputAction: TextInputAction.next,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    hintText: 'What are you working on?',
                    prefixIcon: Icon(Icons.bubble_chart_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bio,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timezone,
                  textInputAction: TextInputAction.next,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    prefixIcon: Icon(Icons.public_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Timezone is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _avatarUrl,
                  keyboardType: TextInputType.url,
                  maxLength: 2048,
                  decoration: const InputDecoration(
                    labelText: 'Avatar URL',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => unawaited(_save()),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
