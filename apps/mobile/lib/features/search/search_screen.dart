import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import '../messages/room_screen.dart';
import 'search_models.dart';
import 'search_transport.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.transport, super.key});

  final SearchTransport transport;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  SearchResults? _results;
  Object? _error;
  bool _loading = false;
  String? _openingUserId;
  int _requestSerial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    final serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.transport.search(query);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openDirectMessage(SearchUserResult user) async {
    if (_openingUserId != null) return;

    setState(() => _openingUserId = user.id);
    final name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : '@${user.username}';

    try {
      final conversationId = await widget.transport.startDirectConversation(
        user.id,
      );

      try {
        await MobileDataScope.of(context).refreshInbox();
      } catch (_) {
        // The conversation can still be opened directly if refreshing the
        // sidebar snapshot fails because of a temporary network issue.
      }

      if (!mounted) return;
      context.push(
        '/room/conversation/$conversationId',
        extra: RoomScreenArgs(title: name),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open direct message: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Search',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) {
                final query = value.trim();
                if (query.length >= 2) unawaited(_search(query));
              },
              decoration: InputDecoration(
                hintText: 'Search messages, people, and channels',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _debounce?.cancel();
                          _controller.clear();
                          setState(() {
                            _results = null;
                            _error = null;
                            _loading = false;
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final query = _controller.text.trim();
    if (query.length < 2) {
      return const _SearchHint();
    }

    if (_error != null && _results == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.white38),
          const SizedBox(height: 14),
          const Text(
            'Search is unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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

    final results = _results;
    if (results == null) {
      return const SizedBox.shrink();
    }

    if (results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.search_off_rounded, size: 42, color: Colors.white38),
          const SizedBox(height: 14),
          const Text(
            'No results found',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing matches “$query”.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      children: [
        if (results.channels.isNotEmpty) ...[
          const _SectionHeader(title: 'Channels'),
          ...results.channels.map(_channelTile),
          const SizedBox(height: 10),
        ],
        if (results.users.isNotEmpty) ...[
          const _SectionHeader(title: 'People'),
          ...results.users.map(_userTile),
          const SizedBox(height: 10),
        ],
        if (results.messages.isNotEmpty) ...[
          const _SectionHeader(title: 'Messages'),
          ...results.messages.map(_messageTile),
        ],
      ],
    );
  }

  Widget _channelTile(SearchChannelResult channel) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: const Icon(Icons.tag_rounded),
      title: Text(channel.name),
      subtitle: const Text('Channel'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        context.push(
          '/room/channel/${channel.id}',
          extra: RoomScreenArgs(title: '#${channel.name}'),
        );
      },
    );
  }

  Widget _userTile(SearchUserResult user) {
    final name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : '@${user.username}';
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final opening = _openingUserId == user.id;

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF153039),
        child: Text(letter),
      ),
      title: Text(name),
      subtitle: Text('@${user.username}'),
      trailing: opening
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline_rounded),
      onTap: _openingUserId == null
          ? () => unawaited(_openDirectMessage(user))
          : null,
    );
  }

  Widget _messageTile(SearchMessageResult message) {
    final data = MobileDataScope.of(context);
    final sender = message.displayName.trim().isNotEmpty
        ? message.displayName.trim()
        : '@${message.username}';
    final destination = _messageDestination(data, message);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF153039),
        child: Icon(Icons.chat_bubble_outline_rounded, size: 19),
      ),
      title: Text(
        message.body.trim().isEmpty ? 'Attachment message' : message.body.trim(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$sender • ${destination.label}'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: destination.path == null
          ? null
          : () {
              context.push(
                destination.path!,
                extra: RoomScreenArgs(title: destination.title),
              );
            },
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 100),
        Icon(Icons.manage_search_rounded, size: 46, color: Color(0xFF68E0CF)),
        SizedBox(height: 16),
        Text(
          'Search across PulseMesh',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text(
          'Find messages you can access, people in shared workspaces, and available channels.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, height: 1.4),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

({String label, String title, String? path}) _messageDestination(
  MobileDataController data,
  SearchMessageResult message,
) {
  if (message.channelId != null) {
    for (final channel in data.inbox.channels) {
      if (channel.id == message.channelId) {
        return (
          label: '#${channel.name}',
          title: '#${channel.name}',
          path: '/room/channel/${channel.id}',
        );
      }
    }
    return (
      label: 'Channel',
      title: 'Search result',
      path: '/room/channel/${message.channelId}',
    );
  }

  if (message.conversationId != null) {
    for (final conversation in data.inbox.conversations) {
      if (conversation.id != message.conversationId) continue;
      final customName = conversation.name?.trim();
      final title = customName != null && customName.isNotEmpty
          ? customName
          : conversation.kind == 'group'
          ? 'Group conversation'
          : 'Direct message';
      return (
        label: title,
        title: title,
        path: '/room/conversation/${conversation.id}',
      );
    }
    return (
      label: 'Conversation',
      title: 'Search result',
      path: '/room/conversation/${message.conversationId}',
    );
  }

  return (label: 'Message', title: 'Search result', path: null);
}
