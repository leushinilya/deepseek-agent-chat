import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({
    required this.repository,
    super.key,
  });

  final AgentChatRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) => Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('createAgentButton'),
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Создать агента'),
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
                      Text('ИИ-агенты',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text(
                        'Настройте роль, инструкции и модель каждого помощника.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 22),
                      if (repository.agents.isEmpty)
                        Expanded(child: _empty(context))
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: repository.agents.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _card(context, repository.agents[index]),
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
            const Icon(Icons.smart_toy_outlined,
                size: 48, color: Color(0xFF7A8496)),
            const SizedBox(height: 14),
            Text('Агентов пока нет',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Создайте первого агента и начните чат.',
                style: TextStyle(color: Color(0xFF667085))),
          ]),
        ),
      );

  Widget _card(BuildContext context, AiAgent agent) => AppSurface(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: agent.model == AgentModel.localGigaChat
                  ? const Color(0xFFEAF8F1)
                  : const Color(0xFFE8EDFF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              agent.model == AgentModel.localGigaChat
                  ? Icons.computer_rounded
                  : Icons.cloud_outlined,
              color: agent.model == AgentModel.localGigaChat
                  ? const Color(0xFF16794B)
                  : const Color(0xFF3659D9),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(agent.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(agent.model.title,
                  style: const TextStyle(color: Color(0xFF667085))),
              Text('Изменён ${formatDate(agent.updatedAt)}',
                  style:
                      const TextStyle(color: Color(0xFF98A2B3), fontSize: 12)),
            ]),
          ),
          IconButton(
            key: Key('editAgent-${agent.id}'),
            tooltip: 'Редактировать',
            onPressed: () => _edit(context, agent),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: Key('deleteAgent-${agent.id}'),
            tooltip: 'Удалить',
            onPressed: () => _delete(context, agent),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ]),
      );

  Future<void> _edit(BuildContext context, [AiAgent? agent]) async {
    final result = await showDialog<_AgentDraft>(
      context: context,
      builder: (_) => _AgentDialog(agent: agent),
    );
    if (result == null) return;
    if (agent == null) {
      repository.createAgent(
        name: result.name,
        systemPrompt: result.systemPrompt,
        model: result.model,
      );
    } else {
      repository.updateAgent(agent.copyWith(
        name: result.name,
        systemPrompt: result.systemPrompt,
        model: result.model,
      ));
    }
  }

  Future<void> _delete(BuildContext context, AiAgent agent) async {
    final taskCount = repository.taskCountForAgent(agent.id);
    final chatCount = repository.chatCountForAgent(agent.id);
    if (taskCount > 0 || chatCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Нельзя удалить агента'),
          content: Text(
            'С агентом связаны задачи: $taskCount, чаты: $chatCount. '
            'Сначала назначьте задачам другого агента и удалите его чаты.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Понятно')),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить агента?'),
        content: Text('Агент «${agent.name}» будет удалён безвозвратно.'),
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
    if (confirmed == true) repository.deleteAgent(agent.id);
  }
}

class _AgentDraft {
  const _AgentDraft(this.name, this.systemPrompt, this.model);
  final String name;
  final String systemPrompt;
  final AgentModel model;
}

class _AgentDialog extends StatefulWidget {
  const _AgentDialog({this.agent});
  final AiAgent? agent;

  @override
  State<_AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends State<_AgentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.agent?.name);
  late final _prompt = TextEditingController(text: widget.agent?.systemPrompt);
  late var _model = widget.agent?.model ?? AgentModel.localGigaChat;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.agent == null ? 'Новый ИИ-агент' : 'Редактирование агента'),
        content: SizedBox(
          width: 560,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  key: const Key('agentNameField'),
                  controller: _name,
                  autofocus: true,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Имя агента'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('systemPromptField'),
                  controller: _prompt,
                  minLines: 5,
                  maxLines: 10,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Системный промт',
                    alignLabelWithHint: true,
                    hintText: 'Опишите роль, правила и стиль ответов агента',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<AgentModel>(
                  key: const Key('agentModelField'),
                  initialValue: _model,
                  decoration: const InputDecoration(labelText: 'Модель'),
                  items: [
                    for (final model in AgentModel.values)
                      DropdownMenuItem(value: model, child: Text(model.title)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _model = value);
                  },
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveAgentButton'),
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context,
                  _AgentDraft(_name.text.trim(), _prompt.text.trim(), _model));
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
