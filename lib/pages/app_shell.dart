import 'package:flutter/material.dart';

import '../agents/llm_provider.dart';
import '../agents/repository.dart';
import 'agents_page.dart';
import 'chats_page.dart';
import 'comparison_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.repository, super.key});
  final AgentChatRepository repository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ComparisonPage(),
      AgentsPage(
        repository: widget.repository,
        onShowChats: () => setState(() => _index = 2),
      ),
      ChatsPage(
        repository: widget.repository,
        providerFactory: BackendLlmProvider.new,
        onShowAgents: () => setState(() => _index = 1),
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final content = IndexedStack(index: _index, children: pages);
      if (!wide) {
        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.compare_arrows_rounded),
                label: 'Сравнение',
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy_rounded),
                label: 'ИИ-агенты',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: 'Чаты',
              ),
            ],
          ),
        );
      }
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.75,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.compare_arrows_rounded),
                label: Text('Сравнение'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy_rounded),
                label: Text('ИИ-агенты'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: Text('Чаты'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ]),
      );
    });
  }
}
