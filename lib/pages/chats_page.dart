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
    required this.taskId,
    required this.providerFactory,
    super.key,
  });

  final AgentChatRepository repository;
  final String taskId;
  final LlmProviderFactory providerFactory;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final task = repository.taskById(taskId);
          final chats = repository.chats
              .where((chat) => chat.taskId == taskId)
              .toList(growable: false);
          return Scaffold(
            appBar: AppBar(title: Text('Чаты · ${task?.title ?? 'Задача'}')),
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
                        Text(task?.title ?? 'Чаты задачи',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        const Text('Чаты, связанные с этой задачей.',
                            style: TextStyle(color: Color(0xFF667085))),
                        const SizedBox(height: 22),
                        if (chats.isEmpty)
                          Expanded(child: _empty(context))
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: chats.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  _card(context, chats[index]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
                  ? 'Сначала создайте ИИ-агента в настройках.'
                  : 'Начните новый диалог для этой задачи.',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ]),
        ),
      );

  Widget _card(BuildContext context, AgentChat chat) {
    final task = repository.taskById(chat.taskId);
    final agent = repository.agentById(task?.agentId ?? chat.agentId);
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
                      '${agent?.name ?? 'Агент недоступен'} · ${task?.title ?? 'Задача недоступна'}',
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

  void _create(BuildContext context) {
    final task = repository.taskById(taskId);
    final agent = repository.agentById(task?.agentId ?? '');
    if (task == null || agent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Для задачи должен быть выбран ИИ-агент.')));
      return;
    }
    final chat = repository.createChat(taskId: taskId);
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
