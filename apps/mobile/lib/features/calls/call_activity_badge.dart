import 'dart:async';

import 'package:flutter/material.dart';

import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'call_activity_screen.dart';
import 'call_transport.dart';

final ValueNotifier<int> callActivityUnreadCount = ValueNotifier<int>(0);

class CallActivityBadgeIcon extends StatefulWidget {
  const CallActivityBadgeIcon({
    required this.icon,
    super.key,
  });

  final IconData icon;

  @override
  State<CallActivityBadgeIcon> createState() => _CallActivityBadgeIconState();
}

class _CallActivityBadgeIconState extends State<CallActivityBadgeIcon> {
  MobileDataController? _data;
  CallTransport? _transport;
  StreamSubscription<Map<String, dynamic>>? _events;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = MobileDataScope.of(context);
    final transport = CallTransportScope.maybeOf(context);

    if (!identical(_data, data)) {
      _events?.cancel();
      _data = data;
      _events = data.realtimeEvents.listen(_handleRealtimeEvent);
    }

    if (!identical(_transport, transport)) {
      _transport = transport;
      unawaited(_reload());
    }
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'call.ended' || type == 'call.invite.updated') {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final transport = _transport;
    if (transport == null) {
      callActivityUnreadCount.value = 0;
      return;
    }

    try {
      callActivityUnreadCount.value = await transport.unreadMissedCount();
    } catch (_) {
      // Keep the previous badge while temporarily offline.
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: callActivityUnreadCount,
      builder: (context, count, _) {
        final base = Icon(widget.icon);
        if (count <= 0) return base;

        return Badge(
          label: Text(count > 99 ? '99+' : '$count'),
          child: base,
        );
      },
    );
  }
}
