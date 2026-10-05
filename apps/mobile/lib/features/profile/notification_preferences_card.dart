import 'dart:async';

import 'package:flutter/material.dart';

import 'notification_preference.dart';
import 'profile_transport.dart';

class NotificationPreferencesCard extends StatefulWidget {
  const NotificationPreferencesCard({
    required this.transport,
    required this.defaultTimezone,
    super.key,
  });

  final ProfileTransport transport;
  final String defaultTimezone;

  @override
  State<NotificationPreferencesCard> createState() =>
      _NotificationPreferencesCardState();
}

class _NotificationPreferencesCardState
    extends State<NotificationPreferencesCard> {
  late final TextEditingController _timezone;
  String _level = 'all';
  bool _quietHoursEnabled = false;
  TimeOfDay _start = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 8, minute: 0);
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _timezone = TextEditingController(text: widget.defaultTimezone);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant NotificationPreferencesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_quietHoursEnabled &&
        _timezone.text == oldWidget.defaultTimezone &&
        widget.defaultTimezone != oldWidget.defaultTimezone) {
      _timezone.text = widget.defaultTimezone;
    }
  }

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preference =
          await widget.transport.fetchGlobalNotificationPreference();
      if (!mounted) return;
      final quiet = preference.quietHours;
      setState(() {
        _level = _normalizedLevel(preference.level);
        _quietHoursEnabled = quiet != null;
        if (quiet != null) {
          _start = _parseTime(quiet.start, fallback: _start);
          _end = _parseTime(quiet.end, fallback: _end);
          _timezone.text = quiet.timezone;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final timezone = _timezone.text.trim();
    if (_quietHoursEnabled && timezone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timezone is required for quiet hours.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final quietHours = _quietHoursEnabled
          ? NotificationQuietHours(
              start: _formatTime(_start),
              end: _formatTime(_end),
              timezone: timezone,
            )
          : null;
      await widget.transport.updateGlobalNotificationPreference(
        NotificationPreference(level: _level, quietHours: quietHours),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update notifications: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
          const Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: Color(0xFF68E0CF)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose what reaches you by default. Channel and conversation overrides still take priority.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load notification preferences.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    unawaited(_load());
                  },
                  child: const Text('Retry'),
                ),
              ],
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: const InputDecoration(
                labelText: 'Default notification level',
                prefixIcon: Icon(Icons.tune_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All messages')),
                DropdownMenuItem(value: 'mentions', child: Text('Mentions only')),
                DropdownMenuItem(value: 'nothing', child: Text('Nothing')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _level = value);
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Quiet hours'),
              subtitle: const Text(
                'Mute routine notifications during a daily window.',
              ),
              value: _quietHoursEnabled,
              onChanged: (value) => setState(() => _quietHoursEnabled = value),
            ),
            if (_quietHoursEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_pickTime(start: true)),
                      icon: const Icon(Icons.bedtime_outlined),
                      label: Text('From ${_start.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_pickTime(start: false)),
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: Text('Until ${_end.format(context)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _timezone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Quiet-hours timezone',
                  hintText: 'Asia/Gaza',
                  prefixIcon: Icon(Icons.public_rounded),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('profile-save-notifications'),
                onPressed: _saving ? null : () => unawaited(_save()),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save notification settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _normalizedLevel(String level) {
  if (level == 'mentions' || level == 'nothing') return level;
  return 'all';
}

TimeOfDay _parseTime(String value, {required TimeOfDay fallback}) {
  final parts = value.split(':');
  if (parts.length != 2) return fallback;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return fallback;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatTime(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
