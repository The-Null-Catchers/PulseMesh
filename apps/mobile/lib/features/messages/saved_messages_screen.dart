import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'message_actions_transport.dart';
import 'room_screen.dart';
import 'saved_message.dart';

class SavedMessagesTransportScope extends InheritedWidget {
  const SavedMessagesTransportScope({
    required this.transport,
    required super.child,
    super.key,
  });

  final MessageActionsTransport transport;

  static MessageActionsTransport of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SavedMessagesTransportScope>();
    assert(scope != null, 'SavedMessagesTransportScope is missing');
    return scope!.transport;
  }

  @override
  bool updateShouldNotify(SavedMessagesTransportScope oldWidget) {
    return !identical(oldWidget.transport, transport);
  }
}

class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({super.key});

  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<SavedMessage> _items = const [];
  bool _loading = true;
  bool _didLoad = false;
  Object? _error;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await SavedMessagesTransportScope.of(context)
          .savedMessages(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _editNote(SavedMessage item) async {
    final controller = TextEditingController(text: item.note ?? '');
    final note = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Private note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'Add a note only you can see',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;

    try {
      await SavedMessagesTransportScope.of(context).bookmarkMessage(
        messageId: item.messageId,
        note: note.trim().isEmpty ? null : note.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _remove(SavedMessage item) async {
    try {
      await SavedMessagesTransportScope.of(context)
          .removeBookmark(messageId: item.messageId);
      if (!mounted) return;
      setState(() {
        _items = _items
            .where((saved) => saved.messageId != item.messageId)
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved message action failed: $error')),
    );
  }

  void _openMessage(SavedMessage item) {
    final message = item.message;
    final channelId = message.channelId;
    final conversationId = message.conversationId;
    if (channelId != null) {
      context.push(
        '/room/channel/$channelId',
        extra: const RoomScreenArgs(title: 'Saved message'),
      );
      return;
    }
    if (conversationId != null) {
      context.push(
        '/room/conversation/$conversationId',
        extra: const RoomScreenArgs(title: 'Saved message'),
      );
    }
  }

  List<SavedMessage> get _filteredItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _items;

    return _items.where((item) {
      final message = item.message;
      final sender = message.sender;
      return message.body.toLowerCase().contains(query) ||
          (item.note ?? '').toLowerCase().contains(query) ||
          sender.displayName.toLowerCase().contains(query) ||
          sender.username.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Saved Messages',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.cloud_off_rounded, size: 40, color: Colors.white38),
          const SizedBox(height: 16),
          const Text(
            'Could not load saved messages',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 120),
          Icon(
            Icons.bookmark_border_rounded,
            size: 42,
            color: Color(0xFF68E0CF),
          ),
          SizedBox(height: 16),
          Text(
            'Nothing saved yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Save a message from any conversation and it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.4),
          ),
        ],
      );
    }

    final items = _filteredItems;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search saved messages and notes',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  size: 42,
                  color: Colors.white38,
                ),
                const SizedBox(height: 14),
                const Text(
                  'No saved messages found',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nothing matches “${_query.trim()}”.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          )
        else
          ...items.indexed.expand((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return [
              if (index > 0) const SizedBox(height: 10),
              _savedMessageCard(item),
            ];
          }),
      ],
    );
  }

  Widget _savedMessageCard(SavedMessage item) {
    final sender = item.message.sender;
    final senderName = sender.displayName.trim().isNotEmpty
        ? sender.displayName.trim()
        : '@${sender.username}';
    final body = item.message.body.trim();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMessage(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF153A39),
                    child: Icon(
                      Icons.bookmark_rounded,
                      color: Color(0xFF68E0CF),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(item.message.createdAt),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit private note',
                    onPressed: () => unawaited(_editNote(item)),
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
                  IconButton(
                    tooltip: 'Remove saved message',
                    onPressed: () => unawaited(_remove(item)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
              if ((item.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1468E0CF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x3368E0CF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PRIVATE NOTE',
                        style: TextStyle(
                          color: Color(0xFF68E0CF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.note!.trim(),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day  $hour:$minute';
}
