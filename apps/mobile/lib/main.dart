import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const ProviderScope(child: PulseMeshApp()));
}

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/messages', builder: (_, _) => const PlaceholderScreen(title: 'Messages')),
        GoRoute(path: '/activity', builder: (_, _) => const PlaceholderScreen(title: 'Activity')),
        GoRoute(path: '/profile', builder: (_, _) => const PlaceholderScreen(title: 'Profile')),
      ],
    ),
  ],
);

class PulseMeshApp extends StatelessWidget {
  const PulseMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF68E0CF),
      brightness: Brightness.dark,
      surface: const Color(0xFF0B171C),
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PulseMesh',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF071015),
      ),
      routerConfig: router,
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  int indexFor(String location) {
    if (location.startsWith('/messages')) return 1;
    if (location.startsWith('/activity')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indexFor(location),
        onDestinationSelected: (index) {
          const paths = ['/home', '/messages', '/activity', '/profile'];
          context.go(paths[index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const channels = ['general', 'backend', 'mobile', 'design', 'random'];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: const Color(0xFF071015),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The Null Catchers', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('PulseMesh workspace', style: TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded)),
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF153039),
                child: Text('M'),
              ),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF12312F), Color(0xFF112638)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x3368E0CF)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: Color(0xFF68E0CF)),
                      SizedBox(width: 8),
                      Text('Realtime workspace', style: TextStyle(color: Color(0xFF9AF5E8))),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Good evening, Mohammed',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '3 teammates are online and #backend has 6 unread messages.',
                    style: TextStyle(color: Colors.white60, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Channels',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white54),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final channel = channels[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                tileColor: channel == 'backend' ? const Color(0x1468E0CF) : null,
                leading: const Icon(Icons.tag_rounded),
                title: Text(channel),
                subtitle: channel == 'backend'
                    ? const Text('API deployment finished', maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: channel == 'backend'
                    ? const Badge(label: Text('6'))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () {},
              ),
            );
          },
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(18, 22, 18, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Voice',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white54),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              leading: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF68E0CF)),
              title: const Text('Daily sync'),
              subtitle: const Text('Mohammed, Lama +1'),
              trailing: FilledButton.tonal(onPressed: () {}, child: const Text('Join')),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}
