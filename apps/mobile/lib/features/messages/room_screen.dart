import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../offline/models.dart';
import '../inbox/inbox_realtime.dart';
import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'room_message.dart';

class RoomScreenArgs {
  const RoomScreenArgs({
    required this.title,
    this.encrypted = false,
  });

  final String title;
  final bool encrypted;
}

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
  RoomMessage? _replyingTo;
  RoomMessage? _editingMessage;
  Timer? _typingStopTimer;
  bool _typingSent = false;
  bool _loading = true;
  bool _sending = false;
  bool _refreshingCache = false;
  bool _pickingAttachments = false;
  List<_ComposerAttachment> _composerAttachments = const [];

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

  Future<void> _pickAttachments() async {
    if (widget.encrypted ||
        _editingMessage != null ||
        _pickingAttachments ||
        _composerAttachments.length >= 10) {
      return;
    }

    setState(() => _pickingAttachments = true);
    try {
      final pickedFiles = await FilePicker.pickFiles();
      if (pickedFiles.isEmpty || !mounted) return;

      final remaining = 10 - _composerAttachments.length;
      final picked = pickedFiles
          .where((file) => file.path != null)
          .take(remaining)
          .toList(growable: false);

      for (var index = 0; index < picked.length; index += 1) {
        final file = picked[index];
        final path = file.path!;
        final sizeBytes = file.lengthSync() ?? await file.length() ?? 0;
        if (sizeBytes <= 0) continue;

        final item = _ComposerAttachment(
          localId:
              '${DateTime.now().microsecondsSinceEpoch}-$index-${file.name}',
          path: path,
          name: file.name,
          mimeType: lookupMimeType(path) ?? 'application/octet-stream',
          sizeBytes: sizeBytes,
          progress: 0,
          status: _ComposerAttachmentStatus.uploading,
        );

        setState(() {
          _composerAttachments = [..._composerAttachments, item];
        });
        unawaited(_uploadComposerAttachment(item));
      }
    } finally {
      if (mounted) {
        setState(() => _pickingAttachments = false);
      }
    }
  }

  Future<void> _uploadComposerAttachment(_ComposerAttachment item) async {
    final data = _data;
    if (data == null) return;

    try {
      final attachment = await data.uploadAttachment(
        path: item.path,
        name: item.name,
        mimeType: item.mimeType,
        sizeBytes: item.sizeBytes,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          _updateComposerAttachment(
            item.localId,
            (current) => current.copyWith(
              progress: (sent / total).clamp(0, 1),
            ),
          );
        },
      );

      if (!mounted) return;
      final stillSelected =
          _composerAttachments.any((entry) => entry.localId == item.localId);
      if (!stillSelected) {
        unawaited(data.deleteUploadedAttachment(attachment.id));
        return;
      }

      _updateComposerAttachment(
        item.localId,
        (current) => current.copyWith(
          progress: 1,
          status: _ComposerAttachmentStatus.ready,
          attachment: attachment,
          error: null,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _updateComposerAttachment(
        item.localId,
        (current) => current.copyWith(
          status: _ComposerAttachmentStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  void _updateComposerAttachment(
    String localId,
    _ComposerAttachment Function(_ComposerAttachment current) update,
  ) {
    if (!mounted) return;
    final index =
        _composerAttachments.indexWhere((item) => item.localId == localId);
    if (index < 0) return;

    final next = [..._composerAttachments];
    next[index] = update(next[index]);
    setState(() => _composerAttachments = next);
  }

  Future<void> _removeComposerAttachment(_ComposerAttachment item) async {
    setState(() {
      _composerAttachments = _composerAttachments
          .where((candidate) => candidate.localId != item.localId)
          .toList(growable: false);
    });

    final fileId = item.attachment?.id;
    if (fileId != null) {
      try {
        await _data?.deleteUploadedAttachment(fileId);
      } catch (_) {
        // Cleanup is best-effort. The server can garbage-collect unattached files.
      }
    }
  }

  Future<void> _retryComposerAttachment(_ComposerAttachment item) async {
    _updateComposerAttachment(
      item.localId,
      (current) => current.copyWith(
        progress: 0,
        status: _ComposerAttachmentStatus.uploading,
        error: null,
      ),
    );
    await _uploadComposerAttachment(item);
  }

  Future<void> _discardComposerAttachments() async {
    final discarded = _composerAttachments;
    if (discarded.isEmpty) return;
    setState(() => _composerAttachments = const []);

    for (final item in discarded) {
      final fileId = item.attachment?.id;
      if (fileId == null) continue;
      try {
        await _data?.deleteUploadedAttachment(fileId);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> _downloadAttachment(RoomAttachment attachment) async {
    try {
      final uri = await _data?.attachmentDownloadUrl(attachment.id);
      if (uri == null) return;
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open download URL');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this attachment.')),
      );
    }
  }

  Future<void> _send() async {
    if (_sending || widget.encrypted) return;

    final body = _composer.text.trim();
    final editing = _editingMessage;
    final reply = _replyingTo;
    final attachments = _composerAttachments;

    if (attachments.any(
      (item) => item.status == _ComposerAttachmentStatus.uploading,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for attachments to finish uploading.')),
      );
      return;
    }

    if (attachments.any(
      (item) => item.status == _ComposerAttachmentStatus.failed,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retry or remove failed attachments first.')),
      );
      return;
    }

    final readyAttachments = attachments
        .map((item) => item.attachment)
        .whereType<RoomAttachment>()
        .toList(growable: false);

    if (editing == null && body.isEmpty && readyAttachments.isEmpty) return;
    if (editing != null && body.isEmpty) return;

    setState(() => _sending = true);
    _stopTyping();
    _composer.clear();

    try {
      if (editing != null && editing.serverId != null) {
        await _data?.editRoomMessage(
          room: widget.room,
          messageId: editing.serverId!,
          body: body,
        );
      } else {
        await _data?.sendRoomMessage(
          widget.room,
          body,
          replyToMessageId: reply?.serverId,
          attachmentIds:
              readyAttachments.map((attachment) => attachment.id).toList(),
        );
      }

      if (!mounted) return;
      setState(() {
        _editingMessage = null;
        _replyingTo = null;
        _composerAttachments = const [];
      });
      await _loadFromCache();
      _composerFocus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      _composer.text = body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editing == null
                ? 'Could not queue this message.'
                : 'Could not edit this message.',
          ),
        ),
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
        const SnackBar(
          content: Text('Retry will resume when connectivity returns.'),
        ),
      );
    }
  }

  void _onComposerChanged(String value) {
    if (widget.encrypted || _editingMessage != null) return;

    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }

    if (!_typingSent) {
      _data?.setTyping(widget.room, typing: true);
      _typingSent = true;
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;

    if (!_typingSent) return;
    _typingSent = false;
    _data?.setTyping(widget.room, typing: false);
  }

  void _startReply(RoomMessage message) {
    if (message.serverId == null || widget.encrypted) return;
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  void _startEdit(RoomMessage message) {
    if (message.serverId == null || message.encrypted || widget.encrypted) {
      return;
    }

    _stopTyping();
    unawaited(_discardComposerAttachments());
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _composer.text = message.body;
      _composer.selection = TextSelection.collapsed(
        offset: _composer.text.length,
      );
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerContext() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
      _composer.clear();
    });
    _stopTyping();
  }

  Future<void> _setReaction(
    RoomMessage message,
    String emoji, {
    required bool active,
  }) async {
    final messageId = message.serverId;
    if (messageId == null) return;

    try {
      await _data?.setRoomReaction(
        room: widget.room,
        messageId: messageId,
        emoji: emoji,
        active: active,
      );
      await _loadFromCache();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update reaction.')),
      );
    }
  }

  Future<void> _deleteMessage(
    RoomMessage message, {
    required String scope,
  }) async {
    final messageId = message.serverId;
    if (messageId == null) return;

    try {
      await _data?.deleteRoomMessage(
        room: widget.room,
        messageId: messageId,
        scope: scope,
      );
      if (!mounted) return;

      if (_editingMessage?.serverId == messageId ||
          _replyingTo?.serverId == messageId) {
        _cancelComposerContext();
      }
      await _loadFromCache();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this message.')),
      );
    }
  }

  Future<void> _showMessageActions(RoomMessage message) async {
    if (message.serverId == null) {
      if (message.failed) {
        await _retry(message);
      }
      return;
    }

    final data = _data;
    if (data == null) return;
    final isMine = message.senderId != null &&
        message.senderId == data.currentUserId;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0C171C),
      builder: (sheetContext) {
        const quickReactions = ['👍', '🔥', '😂', '❤️', '👀'];

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 54,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: quickReactions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final emoji = quickReactions[index];
                      RoomReaction? existing;
                      for (final reaction in message.reactions) {
                        if (reaction.emoji == emoji) {
                          existing = reaction;
                          break;
                        }
                      }
                      return ActionChip(
                        label: Text(
                          existing == null
                              ? emoji
                              : '$emoji ${existing.count}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        side: BorderSide(
                          color: existing?.reactedByMe == true
                              ? const Color(0xFF68E0CF)
                              : const Color(0xFF24404A),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          unawaited(
                            _setReaction(
                              message,
                              emoji,
                              active: existing?.reactedByMe != true,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (!widget.encrypted)
                  ListTile(
                    leading: const Icon(Icons.reply_rounded),
                    title: const Text('Reply'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startReply(message);
                    },
                  ),
                if (isMine && !message.encrypted && !widget.encrypted)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit message'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startEdit(message);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Delete for me'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_deleteMessage(message, scope: 'self'));
                  },
                ),
                if (isMine)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Delete for everyone',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_deleteMessage(message, scope: 'everyone'));
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _stopTyping();
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
    final typingText = _typingText(data);

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
              typingText ?? _connectionText(data),
              style: TextStyle(
                fontSize: 11,
                color: typingText != null
                    ? const Color(0xFF68E0CF)
                    : data.offline
                        ? Colors.orangeAccent
                        : Colors.white54,
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
                            final message = _messages[index];
                            return _MessageCard(
                              message: message,
                              replyPreview: _replyPreview(message),
                              isMine: message.senderId != null &&
                                  message.senderId == data.currentUserId,
                              onRetry: _retry,
                              onLongPress: _showMessageActions,
                              onReactionPressed: (reaction) => _setReaction(
                                message,
                                reaction.emoji,
                                active: !reaction.reactedByMe,
                              ),
                              onAttachmentPressed: _downloadAttachment,
                            );
                          },
                        ),
                      ),
          ),
          _ComposerContextBanner(
            replyingTo: _replyingTo,
            editingMessage: _editingMessage,
            onCancel: _cancelComposerContext,
          ),
          _AttachmentComposerTray(
            items: _composerAttachments,
            onRemove: _removeComposerAttachment,
            onRetry: _retryComposerAttachment,
          ),
          _Composer(
            controller: _composer,
            focusNode: _composerFocus,
            encrypted: widget.encrypted,
            sending: _sending,
            editing: _editingMessage != null,
            pickingAttachments: _pickingAttachments,
            attachmentsBusy: _composerAttachments.any(
              (item) => item.status == _ComposerAttachmentStatus.uploading,
            ),
            onPickAttachments: _pickAttachments,
            onChanged: _onComposerChanged,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  String? _replyPreview(RoomMessage message) {
    final replyId = message.replyToMessageId;
    if (replyId == null) return null;

    for (final candidate in _messages) {
      if (candidate.serverId != replyId) continue;
      final body = candidate.encrypted ? 'Encrypted message' : candidate.body;
      final trimmed = body.trim();
      if (trimmed.isEmpty) return 'Reply to an attachment';
      return '${candidate.senderLabel}: ${_shorten(trimmed, 90)}';
    }

    return 'Reply to an earlier message';
  }

  String? _typingText(MobileDataController data) {
    final currentUserId = data.currentUserId;
    final ids = data
        .typingUsersForRoom(widget.room)
        .where((id) => id != currentUserId)
        .toList(growable: false);
    if (ids.isEmpty) return null;

    final names = <String>[];
    for (final id in ids) {
      String? name;
      for (final message in _messages) {
        if (message.senderId == id) {
          name = message.senderLabel;
          break;
        }
      }
      names.add(name ?? 'Someone');
    }

    final unique = names.toSet().toList(growable: false);
    if (unique.length == 1) return '${unique.first} is typing…';
    if (unique.length == 2) {
      return '${unique.first} and ${unique.last} are typing…';
    }
    return '${unique.take(2).join(', ')} and others are typing…';
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.replyPreview,
    required this.isMine,
    required this.onRetry,
    required this.onLongPress,
    required this.onReactionPressed,
    required this.onAttachmentPressed,
  });

  final RoomMessage message;
  final String? replyPreview;
  final bool isMine;
  final Future<void> Function(RoomMessage message) onRetry;
  final Future<void> Function(RoomMessage message) onLongPress;
  final Future<void> Function(RoomReaction reaction) onReactionPressed;
  final Future<void> Function(RoomAttachment attachment) onAttachmentPressed;

  @override
  Widget build(BuildContext context) {
    final body = message.encrypted ? 'Encrypted message' : message.body;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isMine || message.clientMessageId != null
            ? const Color(0xFF10282C)
            : const Color(0xFF0B171C),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: message.failed ? () => onRetry(message) : null,
          onLongPress: () {
            unawaited(onLongPress(message));
          },
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
                      if (replyPreview != null) ...[
                        const SizedBox(height: 7),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13242B),
                            borderRadius: BorderRadius.circular(10),
                            border: const Border(
                              left: BorderSide(
                                color: Color(0xFF68E0CF),
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            replyPreview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                      if (body.isNotEmpty || message.encrypted) ...[
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
                      if (message.attachments.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Column(
                          children: message.attachments
                              .map(
                                (attachment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _MessageAttachmentTile(
                                    attachment: attachment,
                                    onPressed: () {
                                      unawaited(onAttachmentPressed(attachment));
                                    },
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      if (message.reactions.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: message.reactions
                              .map(
                                (reaction) => InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    unawaited(onReactionPressed(reaction));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: reaction.reactedByMe
                                          ? const Color(0x2268E0CF)
                                          : const Color(0xFF13242B),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: reaction.reactedByMe
                                            ? const Color(0xFF68E0CF)
                                            : const Color(0xFF24404A),
                                      ),
                                    ),
                                    child: Text(
                                      '${reaction.emoji} ${reaction.count}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
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

class _ComposerContextBanner extends StatelessWidget {
  const _ComposerContextBanner({
    required this.replyingTo,
    required this.editingMessage,
    required this.onCancel,
  });

  final RoomMessage? replyingTo;
  final RoomMessage? editingMessage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final message = editingMessage ?? replyingTo;
    if (message == null) return const SizedBox.shrink();

    final editing = editingMessage != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1D22),
        border: Border(top: BorderSide(color: Color(0xFF173039))),
      ),
      child: Row(
        children: [
          Icon(
            editing ? Icons.edit_outlined : Icons.reply_rounded,
            size: 18,
            color: const Color(0xFF68E0CF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing ? 'Editing message' : 'Replying to ${message.senderLabel}',
                  style: const TextStyle(
                    color: Color(0xFF68E0CF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _shorten(
                    message.encrypted ? 'Encrypted message' : message.body,
                    90,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
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
    required this.editing,
    required this.pickingAttachments,
    required this.attachmentsBusy,
    required this.onPickAttachments,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool encrypted;
  final bool sending;
  final bool editing;
  final bool pickingAttachments;
  final bool attachmentsBusy;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onChanged;
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
                    onPressed: editing || pickingAttachments
                        ? null
                        : onPickAttachments,
                    icon: pickingAttachments
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          )
                        : const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('room-composer'),
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: editing ? 'Edit message…' : 'Message…',
                        isDense: true,
                      ),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('room-send'),
                    tooltip: editing ? 'Save edit' : 'Send',
                    onPressed: sending || attachmentsBusy ? null : onSend,
                    icon: Icon(
                      editing ? Icons.check_rounded : Icons.arrow_upward_rounded,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _ComposerAttachmentStatus { uploading, ready, failed }

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.localId,
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.progress,
    required this.status,
    this.attachment,
    this.error,
  });

  final String localId;
  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final double progress;
  final _ComposerAttachmentStatus status;
  final RoomAttachment? attachment;
  final String? error;

  _ComposerAttachment copyWith({
    double? progress,
    _ComposerAttachmentStatus? status,
    RoomAttachment? attachment,
    String? error,
  }) {
    return _ComposerAttachment(
      localId: localId,
      path: path,
      name: name,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      attachment: attachment ?? this.attachment,
      error: error,
    );
  }
}

class _AttachmentComposerTray extends StatelessWidget {
  const _AttachmentComposerTray({
    required this.items,
    required this.onRemove,
    required this.onRetry,
  });

  final List<_ComposerAttachment> items;
  final Future<void> Function(_ComposerAttachment item) onRemove;
  final Future<void> Function(_ComposerAttachment item) onRetry;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      decoration: const BoxDecoration(
        color: Color(0xFF091419),
        border: Border(top: BorderSide(color: Color(0xFF173039))),
      ),
      child: SizedBox(
        height: 70,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final failed = item.status == _ComposerAttachmentStatus.failed;
            return Container(
              width: 210,
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF102229),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: failed
                      ? Colors.redAccent
                      : const Color(0xFF24404A),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : item.status == _ComposerAttachmentStatus.ready
                            ? Icons.check_circle_outline_rounded
                            : Icons.upload_file_rounded,
                    size: 20,
                    color: failed
                        ? Colors.redAccent
                        : const Color(0xFF68E0CF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: failed ? () => unawaited(onRetry(item)) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (item.status == _ComposerAttachmentStatus.uploading)
                            LinearProgressIndicator(value: item.progress)
                          else
                            Text(
                              failed ? 'Tap to retry' : _formatBytes(item.sizeBytes),
                              style: TextStyle(
                                color: failed
                                    ? Colors.redAccent
                                    : Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: () => unawaited(onRemove(item)),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MessageAttachmentTile extends StatelessWidget {
  const _MessageAttachmentTile({
    required this.attachment,
    required this.onPressed,
  });

  final RoomAttachment attachment;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = attachment.isImage
        ? Icons.image_outlined
        : attachment.isVideo
            ? Icons.movie_outlined
            : Icons.insert_drive_file_outlined;

    return Material(
      color: const Color(0xFF13242B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 22, color: const Color(0xFF68E0CF)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatBytes(attachment.sizeBytes),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
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

String _shorten(String value, int limit) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= limit) return normalized;
  return '${normalized.substring(0, limit - 1)}…';
}
