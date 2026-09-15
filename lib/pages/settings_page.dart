import 'package:flutter/material.dart';

import '../agents/repository.dart';
import 'agents_page.dart';
import 'comparison_page.dart';
import 'profile_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.repository,
    required this.onShowChats,
    super.key,
  });

  final AgentChatRepository repository;
  final VoidCallback onShowChats;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Настройки'),
            bottom: const TabBar(tabs: [
              Tab(icon: Icon(Icons.person_outline_rounded), text: 'Профиль'),
              Tab(icon: Icon(Icons.compare_arrows_rounded), text: 'Сравнение'),
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'ИИ-агенты'),
            ]),
          ),
          body: TabBarView(children: [
            ProfilePage(repository: repository),
            ComparisonPage(repository: repository),
            AgentsPage(repository: repository, onShowChats: onShowChats),
          ]),
        ),
      );
}
