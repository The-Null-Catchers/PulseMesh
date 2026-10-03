import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'call_transport.dart';

class CallTransportScope extends InheritedWidget {
  const CallTransportScope({
    required this.transport,
    required super.child,
    super.key,
  });

  final CallTransport? transport;

  static CallTransport? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CallTransportScope>()
        ?.transport;
  }

  @override
  bool updateShouldNotify(CallTransportScope oldWidget) {
    return !identical(oldWidget.transport, transport);
  }
}

class CallActivityScreen extends StatefulWidget {
  const CallActivityScreen({super.key});

  @override
  State<CallActivityScreen> createState() => _CallActivityScreenState();
}

class _CallActivityScreenState extends State<CallActivityScreen> {
  Future<List<CallHistoryItem>>? _history;
  StreamSubscription<Map<String, dynamic>>? _events;
  MobileDataController? _data;
  CallTransport? _transport;
  bool _missedOnly = false;
  String? _redialingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = MobileDataScope.of(context);
    final transport = CallTransportScope.maybeOf(context);

    if (!identical(_data, data)) {
      _events?.cancel();
      _data = data;
      _events = data.realtimeEvents.listen((event) {
        final type = event['type'] as String?;
        if (type == 'call.started' ||
            type == 'call.ended' ||
            type == 'call.invite.updated') {
          _reload();
        }
      });
    }

    if (!identical(_transport, transport)) {
      _transport = transport;
      _reload();
    } else {
      _history ??= _load();
    }
  }

  Future<List<CallHistoryItem>> _load() async {
    final transport = _transport;
    if (transport == null) return const [];
    return transport.history(limit: 75);
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _history = _load());
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _history = future);
    await future;
  }

  Future<void> _redial(CallHistoryItem item) async {
    final transport = _transport;
    final conversationId = item.conversationId;
    if (transport == null || conversationId == null || _redialingId != null) {
      return;
    }

    setState(() => _redialingId = item.id);
    try {
      final call = await transport.startConversationCall(
        conversationId,
        kind: item.kind,
      );
      if (!mounted) return;

      final data = _data;
      final title = data == null
          ? 'PulseMesh call'
          : _conversationTitle(data, conversationId);
      final path = item.kind == 'video'
          ? '/call/video/${call.id}'
          : '/call/voice/${call.id}';
      await context.push(
        '$path?conversationId=${Uri.encodeComponent(conversationId)}'
        '&title=${Uri.encodeComponent(title)}',
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _redialingId = null);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: const Color(0xFF071015),
            title: const Text(
              'Activity',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('All')),
                    ButtonSegment(value: true, label: Text('Missed')),
                  ],
                  selected: {_missedOnly},
                  onSelectionChanged: (value) {
                    setState(() => _missedOnly = value.first);
                  },
                ),
              ),
            ],
          ),
          if (_transport == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _CallActivityEmpty(
                icon: Icons.cloud_off_rounded,
                title: 'Call activity unavailable',
                subtitle: 'Reconnect to PulseMesh and try again.',
              ),
            )
          else
            FutureBuilder<List<CallHistoryItem>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CallActivityEmpty(
                      icon: Icons.sync_problem_rounded,
                      title: 'Could not load call activity',
                      subtitle: 'Pull down to retry.',
                      onRetry: _reload,
                    ),
                  );
                }

                final all = snapshot.data ?? const <CallHistoryItem>[];
                final items = _missedOnly
                    ? all.where((item) => item.missed).toList(growable: false)
                    : all;
                if (items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CallActivityEmpty(
                      icon: _missedOnly
                          ? Icons.call_received_rounded
                          : Icons.history_rounded,
                      title: _missedOnly
                          ? 'No missed calls'
                          : 'No call activity yet',
                      subtitle: _missedOnly
                          ? 'Missed calls will appear here.'
                          : 'Voice and video calls will appear here.',
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _CallHistoryTile(
                        item: item,
                        title: _historyTitle(_data, item),
                        redialing: _redialingId == item.id,
                        onRedial: () => unawaited(_redial(item)),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({
    required this.item,
    required this.title,
    required this.redialing,
    required this.onRedial,
  });

  final CallHistoryItem item;
  final String title;
  final bool redialing;
  final VoidCallback onRedial;

  @override
  Widget build(BuildContext context) {
    final video = item.kind == 'video';
    final missed = item.missed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: missed ? const Color(0x14FF6B6B) : const Color(0x08FFFFFF),
        leading: CircleAvatar(
          backgroundColor: missed
              ? const Color(0x332F1717)
              : const Color(0xFF153039),
          child: Icon(
            video ? Icons.videocam_outlined : Icons.call_outlined,
            color: missed ? Colors.redAccent : const Color(0xFF68E0CF),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: missed ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_callStatus(item)} • ${_relativeTime(item.startedAt)}'
            '${_durationSuffix(item)}',
            style: TextStyle(
              color: missed ? Colors.redAccent.shade100 : Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
        trailing: IconButton(
          tooltip: video ? 'Video call again' : 'Call again',
          onPressed: redialing ? null : onRedial,
          icon: redialing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  color: const Color(0xFF68E0CF),
                ),
        ),
      ),
    );
  }
}

class _CallActivityEmpty extends StatelessWidget {
  const _CallActivityEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.white38),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _historyTitle(MobileDataController? data, CallHistoryItem item) {
  final conversationId = item.conversationId;
  if (data != null && conversationId != null) {
    return _conversationTitle(data, conversationId);
  }

  final display = item.creatorDisplayName.trim();
  if (display.isNotEmpty) return display;
  final username = item.creatorUsername.trim();
  if (username.isNotEmpty) return '@$username';
  return 'PulseMesh call';
}

String _conversationTitle(MobileDataController data, String conversationId) {
  for (final conversation in data.inbox.conversations) {
    if (conversation.id != conversationId) continue;
    final name = conversation.name?.trim();
    if (name != null && name.isNotEmpty) return name;

    final names = conversation.members
        .map((member) {
          final display = member.displayName.trim();
          return display.isEmpty ? member.username.trim() : display;
        })
        .where((name) => name.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (names.isNotEmpty) return names.join(', ');
    return conversation.kind == 'group'
        ? 'Group conversation'
        : 'Direct message';
  }
  return 'PulseMesh call';
}

String _callStatus(CallHistoryItem item) {
  if (item.status == 'active') return 'Ongoing ${item.kind} call';
  if (item.missed) return 'Missed ${item.kind} call';
  if (item.direction == 'outgoing') return 'Outgoing ${item.kind} call';
  if (item.inviteStatus == 'declined') return 'Declined ${item.kind} call';
  return 'Incoming ${item.kind} call';
}

String _durationSuffix(CallHistoryItem item) {
  final endedAt = item.endedAt;
  if (!item.joined || endedAt == null) return '';
  final duration = endedAt.difference(item.startedAt);
  if (duration.isNegative) return '';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  if (minutes > 0) return ' • ${minutes}m ${seconds}s';
  return ' • ${seconds}s';
}

String _relativeTime(DateTime value) {
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
