import 'package:flutter/material.dart';

import '../agents/llm_provider.dart';
import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';
import 'chat_page.dart';

typedef LlmProviderFactory = LlmProvider Function();

class ChatsPage extends StatelessWidget {
  const ChatsPage({
    required this.repository,
    required this.providerFactory,
    required this.onShowAgents,
    super.key,
  });

  final AgentChatRepository repository;
  final LlmProviderFactory providerFactory;
  final VoidCallback onShowAgents;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) => Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('createChatButton'),
            onPressed: () => _create(context),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Новый чат'),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 96),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Чаты',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text('Отдельные диалоги с вашими ИИ-агентами.',
                          style: TextStyle(color: Color(0xFF667085))),
                      const SizedBox(height: 22),
                      if (repository.chats.isEmpty)
                        Expanded(child: _empty(context))
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: repository.chats.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _card(context, repository.chats[index]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _empty(BuildContext context) => Center(
        child: AppSurface(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.forum_outlined,
                size: 48, color: Color(0xFF7A8496)),
            const SizedBox(height: 14),
            Text('Чатов пока нет',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              repository.agents.isEmpty
                  ? 'Сначала создайте ИИ-агента.'
                  : 'Выберите агента и начните новый диалог.',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (repository.agents.isEmpty) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onShowAgents,
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('Перейти к агентам'),
              ),
            ],
          ]),
        ),
      );

  Widget _card(BuildContext context, AgentChat chat) {
    final agent = repository.agentById(chat.agentId);
    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        key: Key('openChat-${chat.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: agent == null ? null : () => _open(context, chat),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            const CircleAvatar(child: Icon(Icons.chat_bubble_outline_rounded)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      agent == null
                          ? 'Агент недоступен'
                          : '${agent.name} · ${agent.model.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF667085)),
                    ),
                    Text(formatDate(chat.lastActivityAt),
                        style: const TextStyle(
                            color: Color(0xFF98A2B3), fontSize: 12)),
                  ]),
            ),
            IconButton(
              key: Key('deleteChat-${chat.id}'),
              tooltip: 'Удалить чат',
              onPressed: () => _delete(context, chat),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
          ]),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    if (repository.agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сначала создайте хотя бы одного ИИ-агента.')));
      onShowAgents();
      return;
    }
    final agentId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Выберите агента'),
        children: [
          for (final agent in repository.agents)
            SimpleDialogOption(
              key: Key('selectAgent-${agent.id}'),
              onPressed: () => Navigator.pop(context, agent.id),
              child: ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(agent.name),
                subtitle: Text(agent.model.title),
              ),
            ),
        ],
      ),
    );
    if (agentId == null || !context.mounted) return;
    final chat = repository.createChat(agentId);
    _open(context, chat);
  }

  void _open(BuildContext context, AgentChat chat) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        repository: repository,
        chatId: chat.id,
        provider: providerFactory(),
      ),
    ));
  }

  Future<void> _delete(BuildContext context, AgentChat chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text('История «${chat.title}» будет удалена безвозвратно.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) repository.deleteChat(chat.id);
  }
}
