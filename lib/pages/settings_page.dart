import 'package:flutter/material.dart';

import '../agents/repository.dart';
import 'agents_page.dart';
import 'comparison_page.dart';
import 'profile_page.dart';
import 'state_models_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.repository,
    super.key,
  });

  final AgentChatRepository repository;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Настройки'),
            bottom: const TabBar(isScrollable: true, tabs: [
              Tab(icon: Icon(Icons.person_outline_rounded), text: 'Профиль'),
              Tab(icon: Icon(Icons.compare_arrows_rounded), text: 'Сравнение'),
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'ИИ-агенты'),
              Tab(
                  icon: Icon(Icons.account_tree_outlined),
                  text: 'Модели состояний'),
            ]),
          ),
          body: TabBarView(children: [
            ProfilePage(repository: repository),
            ComparisonPage(repository: repository),
            AgentsPage(repository: repository),
            StateModelsPage(repository: repository),
          ]),
        ),
      );
}
