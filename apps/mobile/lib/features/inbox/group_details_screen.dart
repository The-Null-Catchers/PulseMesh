import 'package:flutter/material.dart';

import '../workspaces/workspace_presence.dart';
import '../workspaces/workspace_transport.dart';
import 'group_management_transport.dart';
import 'inbox_models.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    required this.conversation,
    required this.currentUserId,
    required this.workspaceId,
    required this.workspaceTransport,
    required this.groupTransport,
    super.key,
  });

  final ConversationSummary conversation;
  final String? currentUserId;
  final String workspaceId;
  final WorkspaceTransport workspaceTransport;
  final GroupManagementTransport groupTransport;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late String _name;
  late List<ConversationMemberSummary> _members;
  bool _busy = false;
  bool _loadingDetails = true;
  bool _loadingWorkspaceMembers = true;
  Object? _detailsError;
  Object? _workspaceError;
  List<WorkspacePresenceMember> _workspaceMembers = const [];

  ConversationMemberSummary? get _me {
    for (final member in _members) {
      if (member.id == widget.currentUserId) return member;
    }
    return null;
  }

  bool get _canAdmin => _me?.isAdmin == true;
  bool get _isOwner => _me?.isOwner == true;

  @override
  void initState() {
    super.initState();
    _name = widget.conversation.name?.trim().isNotEmpty == true
        ? widget.conversation.name!.trim()
        : 'Group conversation';
    _members = [...widget.conversation.members];
    _loadGroupDetails();
    _loadWorkspaceMembers();
  }

  Future<void> _loadGroupDetails() async {
    try {
      final details = await widget.groupTransport.groupDetails(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _name = details.name?.trim().isNotEmpty == true
            ? details.name!.trim()
            : _name;
        _members = [...details.members];
        _detailsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _detailsError = error);
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _loadWorkspaceMembers() async {
    try {
      final members = await widget.workspaceTransport.listPresence(widget.workspaceId);
      if (!mounted) return;
      setState(() {
        _workspaceMembers = members;
        _workspaceError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _workspaceError = error);
    } finally {
      if (mounted) setState(() => _loadingWorkspaceMembers = false);
    }
  }

  Future<void> _rename() async {
    if (!_canAdmin || _busy) return;
    final controller = TextEditingController(text: _name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextName == null || nextName == _name || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.groupTransport.renameGroup(
        conversationId: widget.conversation.id,
        name: nextName,
      );
      if (!mounted) return;
      setState(() => _name = nextName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not rename this group.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMember() async {
    if (!_canAdmin || _busy || _loadingWorkspaceMembers) return;

    final existingIds = _members.map((member) => member.id).toSet();
    final candidates = _workspaceMembers
        .where((member) => !existingIds.contains(member.userId))
        .toList(growable: false)
      ..sort((a, b) => _label(a).compareTo(_label(b)));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workspace members available to add.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<WorkspacePresenceMember>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0C171C),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final member = candidates[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(_label(member).characters.first.toUpperCase()),
                ),
                title: Text(_label(member)),
                subtitle: Text('@${member.username}'),
                onTap: () => Navigator.pop(sheetContext, member),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.groupTransport.addMember(
        conversationId: widget.conversation.id,
        userId: selected.userId,
      );
      await _loadGroupDetails();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add this member.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(ConversationMemberSummary member) async {
    if (_busy) return;
    final removingSelf = member.id == widget.currentUserId;
    if (member.isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer ownership before removing the owner.')),
      );
      return;
    }
    if (!removingSelf && !_canAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(removingSelf ? 'Leave group?' : 'Remove member?'),
        content: Text(
          removingSelf
              ? 'You will no longer receive messages from this group.'
              : 'Remove ${_memberLabel(member)} from this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(removingSelf ? 'Leave' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.groupTransport.removeMember(
        conversationId: widget.conversation.id,
        memberId: member.id,
      );
      if (!mounted) return;
      if (removingSelf) {
        Navigator.of(context).pop(true);
        return;
      }
      await _loadGroupDetails();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update group membership.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAdmin(ConversationMemberSummary member) async {
    if (!_isOwner || member.isOwner || member.id == widget.currentUserId || _busy) {
      return;
    }
    final nextRole = member.role == 'admin' ? 'member' : 'admin';
    setState(() => _busy = true);
    try {
      await widget.groupTransport.setMemberRole(
        conversationId: widget.conversation.id,
        memberId: member.id,
        role: nextRole,
      );
      await _loadGroupDetails();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change this member role.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transferOwnership(ConversationMemberSummary member) async {
    if (!_isOwner || member.isOwner || member.id == widget.currentUserId || _busy) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Transfer ownership?'),
        content: Text(
          '${_memberLabel(member)} will become the group owner. You will remain a regular member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.groupTransport.transferOwnership(
        conversationId: widget.conversation.id,
        memberId: member.id,
      );
      await _loadGroupDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_memberLabel(member)} is now the group owner.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not transfer group ownership.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group details'),
        actions: [
          if (_busy || _loadingDetails)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_detailsError != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded),
                title: const Text('Could not refresh group permissions.'),
                trailing: TextButton(
                  onPressed: _loadGroupDetails,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
            title: Text(_name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${_members.length} members'),
            trailing: _canAdmin
                ? IconButton(
                    tooltip: 'Rename group',
                    onPressed: _busy ? null : _rename,
                    icon: const Icon(Icons.edit_outlined),
                  )
                : null,
          ),
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Members',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (_canAdmin)
                TextButton.icon(
                  onPressed: _busy || _loadingWorkspaceMembers ? null : _addMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add'),
                ),
            ],
          ),
          if (_workspaceError != null && _canAdmin)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Workspace members could not be loaded. Retry later.',
                style: TextStyle(color: Colors.amber),
              ),
            ),
          ..._members.map((member) {
            final isMe = member.id == widget.currentUserId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(_memberLabel(member).characters.first.toUpperCase()),
              ),
              title: Text('${_memberLabel(member)}${isMe ? ' (you)' : ''}'),
              subtitle: Text(member.role),
              trailing: member.isOwner
                  ? const Icon(Icons.workspace_premium_rounded, color: Colors.amber)
                  : PopupMenuButton<String>(
                      enabled: !_busy && (_canAdmin || isMe),
                      onSelected: (value) {
                        if (value == 'owner') _transferOwnership(member);
                        if (value == 'role') _toggleAdmin(member);
                        if (value == 'remove') _removeMember(member);
                      },
                      itemBuilder: (_) => [
                        if (_isOwner && !isMe)
                          const PopupMenuItem(
                            value: 'owner',
                            child: Text('Transfer ownership'),
                          ),
                        if (_isOwner && !isMe)
                          PopupMenuItem(
                            value: 'role',
                            child: Text(
                              member.role == 'admin'
                                  ? 'Remove admin role'
                                  : 'Make admin',
                            ),
                          ),
                        if ((_canAdmin && !isMe) || isMe)
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(isMe ? 'Leave group' : 'Remove from group'),
                          ),
                      ],
                    ),
            );
          }),
          if (me != null && !me.isOwner) ...[
            const Divider(height: 32),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _removeMember(me),
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              label: const Text(
                'Leave group',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _memberLabel(ConversationMemberSummary member) {
  final displayName = member.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final username = member.username.trim();
  return username.isEmpty ? 'Member' : username;
}

String _label(WorkspacePresenceMember member) {
  final displayName = member.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final username = member.username.trim();
  return username.isEmpty ? 'Member' : username;
}
