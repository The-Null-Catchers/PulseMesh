from pathlib import Path

path = Path("apps/mobile/lib/main.dart")
text = path.read_text()

replacements = [
    (
        "import 'features/messages/room_screen.dart';\n",
        "import 'features/messages/message_actions_transport.dart';\n"
        "import 'features/messages/room_screen.dart';\n"
        "import 'features/messages/saved_messages_screen.dart';\n",
    ),
    (
        "  late final CallTransport _callTransport;\n",
        "  late final CallTransport _callTransport;\n"
        "  late final MessageActionsTransport _messageActionsTransport;\n",
    ),
    (
        "    _callTransport = DioCallTransport(\n"
        "      baseUrl: widget.config.apiBaseUrl,\n"
        "      accessToken: widget.authSession.accessToken,\n"
        "    );\n"
        "    unawaited(_controller.initialize());\n",
        "    _callTransport = DioCallTransport(\n"
        "      baseUrl: widget.config.apiBaseUrl,\n"
        "      accessToken: widget.authSession.accessToken,\n"
        "    );\n"
        "    _messageActionsTransport = DioMessageActionsTransport(\n"
        "      baseUrl: widget.config.apiBaseUrl,\n"
        "      accessToken: widget.authSession.accessToken,\n"
        "    );\n"
        "    unawaited(_controller.initialize());\n",
    ),
    (
        "    return MobileDataScope(\n"
        "      controller: _controller,\n"
        "      child: PulseMeshApp(callTransport: _callTransport),\n"
        "    );\n",
        "    return SavedMessagesTransportScope(\n"
        "      transport: _messageActionsTransport,\n"
        "      child: MobileDataScope(\n"
        "        controller: _controller,\n"
        "        child: PulseMeshApp(callTransport: _callTransport),\n"
        "      ),\n"
        "    );\n",
    ),
    (
        "    GoRoute(\n      path: '/voice/:id',\n",
        "    GoRoute(\n"
        "      path: '/saved',\n"
        "      builder: (_, _) => const SavedMessagesScreen(),\n"
        "    ),\n"
        "    GoRoute(\n"
        "      path: '/voice/:id',\n",
    ),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"Anchor not found: {old[:80]!r}")
    text = text.replace(old, new, 1)

old_appbar = """          const SliverAppBar(
            floating: true,
            backgroundColor: Color(0xFF071015),
            title: Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
"""
new_appbar = """          SliverAppBar(
            floating: true,
            backgroundColor: const Color(0xFF071015),
            title: const Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                tooltip: 'Saved messages',
                onPressed: () => context.push('/saved'),
                icon: const Icon(Icons.bookmark_outline_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
"""
if old_appbar not in text:
    raise SystemExit("Messages app bar anchor not found")
text = text.replace(old_appbar, new_appbar, 1)
path.write_text(text)
