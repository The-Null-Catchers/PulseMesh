import 'package:flutter/material.dart';

import '../workspaces/workspace_presence.dart';
import '../workspaces/workspace_transport.dart';
import 'inbox_transport.dart';

class CreateGroupConversationScreen extends StatefulWidget {
  const CreateGroupConversationScreen({
    required this.workspaceId,
    required this.currentUserId,
    required this.workspaceTransport,
    required this.inboxTransport,
    super.key,
  });

  final String workspaceId;
  final String? currentUserId;
  final WorkspaceTransport workspaceTransport;
  final InboxTransport inboxTransport;

  @override
  State<CreateGroupConversationScreen> createState() =>
      _CreateGroupConversationScreenState();
}

class _CreateGroupConversationScreenState
    extends State<CreateGroupConversationScreen> {
  final _nameController = TextEditingController();
  final _selectedUserIds = <String>{};
  List<WorkspacePresenceMember> _members = const [];
  bool _loading = true;
  bool _creating = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await widget.workspaceTransport.listPresence(
        widget.workspaceId,
      );
      if (!mounted) return;
      setState(() {
        _members = members
            .where((member) => member.userId != widget.currentUserId)
            .toList(growable: false)
          ..sort((a, b) {
            final aName = _memberName(a).toLowerCase();
            final bName = _memberName(b).toLowerCase();
            return aName.compareTo(bName);
          });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedUserIds.isEmpty || _creating) return;

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final created = await widget.inboxTransport.createGroupConversation(
        name: name,
        memberIds: _selectedUserIds.toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _nameController.text.trim().isNotEmpty && _selectedUserIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: canCreate && !_creating ? _createGroup : null,
            child: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _nameController,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'e.g. Product team',
                  prefixIcon: Icon(Icons.group_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_selectedUserIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selectedUserIds.length} selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: const Color(0xFF29191A),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Could not complete this action.'),
                        ),
                        if (!_creating)
                          TextButton(
                            onPressed: _loading ? null : _loadMembers,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No other workspace members are available yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: _members.length,
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            final selected =
                                _selectedUserIds.contains(member.userId);
                            final name = _memberName(member);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: _creating
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedUserIds.add(member.userId);
                                        } else {
                                          _selectedUserIds.remove(member.userId);
                                        }
                                      });
                                    },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              secondary: CircleAvatar(
                                backgroundColor: const Color(0xFF153039),
                                child: Text(
                                  name.isEmpty
                                      ? '?'
                                      : name.characters.first.toUpperCase(),
                                ),
                              ),
                              title: Text(name),
                              subtitle: Text('@${member.username}'),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

String _memberName(WorkspacePresenceMember member) {
  final displayName = member.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final username = member.username.trim();
  return username.isEmpty ? 'Member' : username;
}
