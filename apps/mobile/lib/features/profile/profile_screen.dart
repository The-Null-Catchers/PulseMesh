import 'dart:async';

import 'package:flutter/material.dart';

import 'profile_model.dart';
import 'profile_session.dart';
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
  List<ProfileSession> _sessions = const [];
  Object? _error;
  Object? _sessionError;
  bool _loading = true;
  bool _loadingSessions = true;
  bool _saving = false;
  final Set<String> _revokingSessions = <String>{};
  bool _revokingOthers = false;

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
      _loadingSessions = true;
      _error = null;
      _sessionError = null;
    });

    await Future.wait([_loadProfile(), _loadSessions()]);
  }

  Future<void> _loadProfile() async {
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

  Future<void> _loadSessions() async {
    try {
      final sessions = await widget.transport.fetchSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loadingSessions = false;
        _sessionError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionError = error;
        _loadingSessions = false;
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

    final displayName = _displayName.text.trim();
    final username = _username.text.trim();
    final bio = _bio.text.trim();
    final status = _status.text.trim();
    final timezone = _timezone.text.trim();
    final avatarUrl = _avatarUrl.text.trim();
    final changes = <String, dynamic>{};

    if (username != existing.username) changes['username'] = username;
    if (displayName != existing.displayName) {
      changes['displayName'] = displayName;
    }
    if (bio != (existing.bio ?? '')) {
      changes['bio'] = bio.isEmpty ? null : bio;
    }
    if (status != (existing.statusText ?? '')) {
      changes['statusText'] = status.isEmpty ? null : status;
    }
    if (timezone != existing.timezone) changes['timezone'] = timezone;
    if (avatarUrl != (existing.avatarUrl ?? '')) {
      changes['avatarUrl'] = avatarUrl.isEmpty ? null : avatarUrl;
    }

    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile changes to save.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final profile = await widget.transport.updateProfile(changes);
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

  Future<void> _revokeSession(ProfileSession session) async {
    if (session.current || _revokingSessions.contains(session.id)) return;
    setState(() => _revokingSessions.add(session.id));
    try {
      await widget.transport.revokeSession(session.id);
      if (!mounted) return;
      setState(() {
        _sessions = _sessions
            .where((item) => item.id != session.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${session.title} signed out.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not revoke session: $error')),
      );
    } finally {
      if (mounted) setState(() => _revokingSessions.remove(session.id));
    }
  }

  Future<void> _revokeAllOtherSessions() async {
    if (_revokingOthers) return;
    final others = _sessions.where((session) => !session.current).toList();
    if (others.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out other devices?'),
        content: Text(
          'This will revoke ${others.length} active ${others.length == 1 ? 'session' : 'sessions'} while keeping this device signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out others'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingOthers = true);
    var failed = 0;
    for (final session in others) {
      try {
        await widget.transport.revokeSession(session.id);
      } catch (_) {
        failed += 1;
      }
    }
    if (!mounted) return;
    await _loadSessions();
    if (!mounted) return;
    setState(() => _revokingOthers = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Other devices were signed out.'
              : 'Signed out ${others.length - failed} devices; $failed could not be revoked.',
        ),
      ),
    );
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
          const Text(
            'Profile',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
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
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) return null;
                    final uri = Uri.tryParse(raw);
                    if (uri == null ||
                        !uri.hasScheme ||
                        (uri.scheme != 'http' && uri.scheme != 'https')) {
                      return 'Enter a valid http(s) URL';
                    }
                    return null;
                  },
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
          const SizedBox(height: 30),
          _buildSessionsSection(),
        ],
      ),
    );
  }

  Widget _buildSessionsSection() {
    final otherSessionCount = _sessions.where((session) => !session.current).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B171C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF24404A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security_rounded, color: Color(0xFF68E0CF)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Security & sessions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Refresh sessions',
                onPressed: _loadingSessions ? null : () => unawaited(_loadSessions()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Review devices that are signed in to your PulseMesh account.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_loadingSessions)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_sessionError != null)
            Column(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                const SizedBox(height: 8),
                Text(
                  'Could not load active sessions: $_sessionError',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            )
          else if (_sessions.isEmpty)
            const Text(
              'No active sessions were returned.',
              style: TextStyle(color: Colors.white54),
            )
          else ...[
            for (final session in _sessions) _SessionTile(
              session: session,
              revoking: _revokingSessions.contains(session.id),
              onRevoke: session.current
                  ? null
                  : () => unawaited(_revokeSession(session)),
            ),
            if (otherSessionCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _revokingOthers
                      ? null
                      : () => unawaited(_revokeAllOtherSessions()),
                  icon: _revokingOthers
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: Text(
                    _revokingOthers
                        ? 'Signing out other devices…'
                        : 'Sign out all other devices',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.revoking,
    required this.onRevoke,
  });

  final ProfileSession session;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: session.current
            ? const Color(0xFF173A3A)
            : const Color(0xFF14252C),
        child: Icon(
          session.current ? Icons.smartphone_rounded : Icons.devices_rounded,
          color: session.current ? const Color(0xFF68E0CF) : Colors.white70,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              session.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (session.current)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x2268E0CF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'This device',
                style: TextStyle(
                  color: Color(0xFF9AF5E8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${session.subtitle}\nLast active ${_formatSessionTime(session.lastActiveAt)}',
          style: const TextStyle(color: Colors.white54, height: 1.35),
        ),
      ),
      isThreeLine: true,
      trailing: session.current
          ? null
          : IconButton(
              tooltip: 'Sign out device',
              onPressed: revoking ? null : onRevoke,
              icon: revoking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
            ),
    );
  }
}

String _formatSessionTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
