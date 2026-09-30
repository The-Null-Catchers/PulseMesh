import 'dart:async';

import 'package:flutter/material.dart';

import '../../offline/models.dart';
import '../inbox/inbox_realtime.dart';
import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'room_message.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    required this.room,
    required this.title,
    required this.encrypted,
    super.key,
  });

  final RoomRef room;
  final String title;
  final bool encrypted;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();

  MobileDataController? _data;
  List<RoomMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _refreshingCache = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MobileDataScope.of(context);
    if (identical(_data, next)) return;

    _data?.removeListener(_onDataChanged);
    _data = next;
    next.addListener(_onDataChanged);
    unawaited(_openRoom());
  }

  Future<void> _openRoom() async {
    final data = _data;
    if (data == null) return;

    await _loadFromCache();
    await data.openRoom(widget.room);
    await _loadFromCache();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _onDataChanged() {
    unawaited(_loadFromCache());
  }

  Future<void> _loadFromCache() async {
    final data = _data;
    if (data == null || _refreshingCache) return;

    _refreshingCache = true;
    try {
      final messages = await data.roomMessages(widget.room);
      if (!mounted) return;
      setState(() => _messages = messages);
    } finally {
      _refreshingCache = false;
    }
  }

  Future<void> _send() async {
    if (_sending || widget.encrypted) return;
    final body = _composer.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    _composer.clear();

    try {
      await _data?.sendRoomMessage(widget.room, body);
      await _loadFromCache();
      _composerFocus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      _composer.text = body;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not queue this message.')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _retry(RoomMessage message) async {
    final clientMessageId = message.clientMessageId;
    if (clientMessageId == null) return;

    try {
      await _data?.retryRoomMessage(clientMessageId);
      await _loadFromCache();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retry will resume when connectivity returns.')),
      );
    }
  }

  @override
  void dispose() {
    final data = _data;
    data?.removeListener(_onDataChanged);
    data?.closeRoom(widget.room);
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MobileDataScope.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF071015),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.encrypted) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: Color(0xFF68E0CF),
                  ),
                ],
              ],
            ),
            Text(
              _connectionText(data),
              style: TextStyle(
                fontSize: 11,
                color: data.offline ? Colors.orangeAccent : Colors.white54,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              await data.refreshRoom(widget.room);
              await _loadFromCache();
            },
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (data.offline) const _OfflineStrip(),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const _EmptyRoom()
                    : RefreshIndicator(
                        onRefresh: () async {
                          await data.refreshRoom(widget.room);
                          await _loadFromCache();
                        },
                        child: ListView.builder(
                          reverse: true,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return _MessageCard(
                              message: _messages[index],
                              onRetry: _retry,
                            );
                          },
                        ),
                      ),
          ),
          _Composer(
            controller: _composer,
            focusNode: _composerFocus,
            encrypted: widget.encrypted,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.onRetry,
  });

  final RoomMessage message;
  final Future<void> Function(RoomMessage message) onRetry;

  @override
  Widget build(BuildContext context) {
    final body = message.encrypted
        ? 'Encrypted message'
        : message.body.isEmpty
            ? 'Attachment'
            : message.body;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: message.clientMessageId != null
            ? const Color(0xFF10282C)
            : const Color(0xFF0B171C),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: message.failed ? () => onRetry(message) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF153039),
                  child: Text(
                    _initial(message.senderLabel),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              message.senderLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(message.createdAt),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          if (message.editedAt != null)
                            const Text(
                              ' • edited',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.encrypted) ...[
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 15,
                              color: Color(0xFF68E0CF),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              body,
                              style: TextStyle(
                                color: message.encrypted
                                    ? Colors.white54
                                    : Colors.white,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _DeliveryState(message: message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryState extends StatelessWidget {
  const _DeliveryState({required this.message});

  final RoomMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.failed) {
      return const Tooltip(
        message: 'Tap to retry',
        child: Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: Colors.redAccent,
        ),
      );
    }
    if (message.sending) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 1.6),
      );
    }
    if (message.clientMessageId != null) {
      return const Icon(
        Icons.done_rounded,
        size: 17,
        color: Color(0xFF68E0CF),
      );
    }
    return const SizedBox(width: 17);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.encrypted,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool encrypted;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Color(0xFF071015),
          border: Border(top: BorderSide(color: Color(0xFF173039))),
        ),
        child: encrypted
            ? const _EncryptedComposerNotice()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attachments',
                    onPressed: null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('room-composer'),
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        isDense: true,
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('room-send'),
                    tooltip: 'Send',
                    onPressed: sending ? null : onSend,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EncryptedComposerNotice extends StatelessWidget {
  const _EncryptedComposerNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.lock_rounded, size: 18, color: Color(0xFF68E0CF)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Encrypted history is protected. Sending unlocks after this device has an E2EE key session.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF2D2515),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: Colors.orangeAccent),
          SizedBox(width: 7),
          Text(
            'Offline • new messages will stay queued on this device',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 42, color: Colors.white30),
            SizedBox(height: 12),
            Text(
              'No messages here yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5),
            Text(
              'Start the conversation from this device.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

String _connectionText(MobileDataController data) {
  if (data.offline) return 'Offline cache';
  return switch (data.realtimeState) {
    MobileRealtimeState.ready => 'Realtime connected',
    MobileRealtimeState.connecting => 'Connecting…',
    MobileRealtimeState.reconnecting => 'Reconnecting…',
    MobileRealtimeState.disconnected => 'Disconnected',
  };
}

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
