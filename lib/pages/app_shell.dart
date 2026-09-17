import 'package:flutter/material.dart';

import '../agents/repository.dart';
import 'projects_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';

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
      SettingsPage(repository: widget.repository),
      ProjectsPage(repository: widget.repository),
      TasksPage(repository: widget.repository),
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
                icon: Icon(Icons.settings_outlined),
                label: 'Настройки',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Проекты',
              ),
              NavigationDestination(
                icon: Icon(Icons.task_alt_outlined),
                selectedIcon: Icon(Icons.task_alt_rounded),
                label: 'Задачи',
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
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: Text('Настройки'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: Text('Проекты'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.task_alt_outlined),
                selectedIcon: Icon(Icons.task_alt_rounded),
                label: Text('Задачи'),
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
