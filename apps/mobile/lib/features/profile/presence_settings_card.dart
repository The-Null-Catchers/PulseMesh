import 'dart:async';

import 'package:flutter/material.dart';

import 'presence_snapshot.dart';
import 'profile_transport.dart';

class PresenceSettingsCard extends StatefulWidget {
  const PresenceSettingsCard({required this.transport, super.key});

  final ProfileTransport transport;

  @override
  State<PresenceSettingsCard> createState() => _PresenceSettingsCardState();
}

class _PresenceSettingsCardState extends State<PresenceSettingsCard> {
  final _customText = TextEditingController();
  PresenceSnapshot? _snapshot;
  String _status = 'online';
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _customText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.transport.fetchPresence();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.status == 'offline' ? 'online' : snapshot.status;
        _customText.text = snapshot.customText ?? '';
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
    setState(() => _saving = true);
    try {
      final text = _customText.text.trim();
      final snapshot = await widget.transport.updatePresence(
        status: _status,
        customText: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _status = snapshot.status == 'offline' ? _status : snapshot.status;
        _customText.text = snapshot.customText ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presence updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update presence: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              Icon(Icons.circle, size: 14, color: Color(0xFF68E0CF)),
              SizedBox(width: 10),
              Text(
                'Presence',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _snapshot == null
                ? 'Control how teammates see your availability.'
                : '${_snapshot!.connectedDevices} connected ${_snapshot!.connectedDevices == 1 ? 'device' : 'devices'}',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load presence: $_error',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_load()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            )
          else ...[
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'online',
                  icon: Icon(Icons.circle, size: 12),
                  label: Text('Online'),
                ),
                ButtonSegment(
                  value: 'idle',
                  icon: Icon(Icons.schedule_rounded),
                  label: Text('Away'),
                ),
                ButtonSegment(
                  value: 'do-not-disturb',
                  icon: Icon(Icons.do_not_disturb_on_rounded),
                  label: Text('DND'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() => _status = selection.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customText,
              maxLength: 120,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Custom status',
                hintText: 'Heads down, back at 3 PM…',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => unawaited(_save()),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Saving…' : 'Update presence'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
