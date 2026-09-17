import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/llm_provider.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';
import 'chats_page.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({required this.repository, super.key});

  final AgentChatRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) => Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('createTaskButton'),
            onPressed: () => _createTask(context),
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('Новая задача'),
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
                      Text('Задачи',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text(
                        'Каждая задача принадлежит проекту и хранит рабочую память своих чатов.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 22),
                      if (repository.tasks.isEmpty)
                        Expanded(child: _empty(context))
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: repository.tasks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _taskCard(context, repository.tasks[index]),
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
            const Icon(Icons.task_alt_rounded,
                size: 48, color: Color(0xFF7A8496)),
            const SizedBox(height: 14),
            Text('Задач пока нет',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              repository.projects.isEmpty
                  ? 'Сначала создайте проект.'
                  : 'Создайте задачу и обязательно выберите для неё проект.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ]),
        ),
      );

  Widget _taskCard(BuildContext context, AgentTask task) {
    final project = repository.projectById(task.projectId);
    final agent = repository.agentById(task.agentId ?? '');
    final workingMemory = repository.workingMemory(task.id);
    final chatCount = repository.chatCountForTask(task.id);
    final state = repository.currentStateForTask(task);
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.assignment_outlined, color: Color(0xFF3659D9)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    '${project?.title ?? 'Проект недоступен'} · ${agent?.name ?? 'Агент не выбран'} · чатов: $chatCount',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('editTask-${task.id}'),
              tooltip: 'Редактировать задачу',
              onPressed: () => _editTask(context, task),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: Key('deleteTask-${task.id}'),
              tooltip: 'Удалить задачу',
              onPressed: () => _deleteTask(context, task),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          if (state == null)
            const Text('Модель состояний не настроена.',
                style: TextStyle(color: Color(0xFF667085)))
          else
            _TaskStateBadge(
              state: state,
              completed: repository.isTaskComplete(task),
            ),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.notes_rounded, size: 18, color: Color(0xFF667085)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Рабочая память',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              key: Key('editWorkingMemory-${task.id}'),
              tooltip: 'Редактировать рабочую память',
              onPressed: () =>
                  _editMemory(context, task, workingMemory.content),
              icon: const Icon(Icons.edit_outlined),
            ),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1E6EF)),
            ),
            child: workingMemory.content.isEmpty
                ? const Text('Рабочая память задачи пуста.',
                    style: TextStyle(
                        color: Color(0xFF667085), fontStyle: FontStyle.italic))
                : SelectableText(workingMemory.content),
          ),
          if (task.stageResults.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Выполненные этапы',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...task.stageResults.map((result) => ExpansionTile(
                  key: Key('taskStageResult-${result.stateId}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(result.stateName),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(result.result),
                    ),
                  ],
                )),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: Key('taskChats-${task.id}'),
            onPressed: () => _openChats(context, task),
            icon: const Icon(Icons.forum_outlined),
            label: Text('Чаты задачи ($chatCount)'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTask(BuildContext context) async {
    if (repository.projects.isEmpty || repository.agents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сначала создайте проект и ИИ-агента.')));
      return;
    }
    final result =
        await showDialog<({String projectId, String agentId, String title})>(
      context: context,
      builder: (_) => _CreateTaskDialog(repository: repository),
    );
    if (result != null) {
      repository.createTask(
        projectId: result.projectId,
        agentId: result.agentId,
        title: result.title,
      );
    }
  }

  void _openChats(BuildContext context, AgentTask task) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatsPage(
        repository: repository,
        taskId: task.id,
        providerFactory: BackendLlmProvider.new,
      ),
    ));
  }

  Future<void> _editMemory(
      BuildContext context, AgentTask task, String initialContent) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _WorkingMemoryDialog(
        task: task,
        initialContent: initialContent,
      ),
    );
    if (value != null) repository.updateWorkingMemory(task.id, value);
  }

  Future<void> _editTask(BuildContext context, AgentTask task) async {
    final result =
        await showDialog<({String projectId, String agentId, String title})>(
      context: context,
      builder: (_) => _CreateTaskDialog(repository: repository, task: task),
    );
    if (result == null) return;
    repository.updateTask(task.copyWith(
      title: result.title,
      agentId: result.agentId,
    ));
  }

  Future<void> _deleteTask(BuildContext context, AgentTask task) async {
    final chatCount = repository.chatCountForTask(task.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(chatCount == 0
            ? 'Задача будет удалена безвозвратно.'
            : 'Все вложенные чаты ($chatCount) и их история будут удалены вместе с задачей.'),
        actions: [
          TextButton(
              key: const Key('cancelDeleteTaskButton'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          FilledButton(
              key: const Key('confirmDeleteTaskButton'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Да')),
        ],
      ),
    );
    if (confirmed == true) repository.deleteTask(task.id);
  }
}

class _TaskStateBadge extends StatelessWidget {
  const _TaskStateBadge({required this.state, required this.completed});

  final TaskStateDefinition state;
  final bool completed;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('taskState-${state.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Color(state.colorValue).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Color(state.colorValue),
          ),
        ),
        child: Text(
          completed ? '${state.name} · завершено' : state.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(state.colorValue),
          ),
        ),
      );
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({required this.repository, this.task});
  final AgentChatRepository repository;
  final AgentTask? task;

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  late String _projectId;
  late String _agentId;
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _projectId = widget.task?.projectId ?? widget.repository.projects.first.id;
    _agentId = widget.task?.agentId ?? widget.repository.agents.first.id;
    _title = TextEditingController(text: widget.task?.title ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.task == null ? 'Новая задача' : 'Редактировать задачу'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              key: const Key('taskProjectField'),
              initialValue: _projectId,
              decoration: const InputDecoration(labelText: 'Проект'),
              items: widget.repository.projects
                  .map((project) => DropdownMenuItem(
                        value: project.id,
                        child: Text(project.title),
                      ))
                  .toList(),
              onChanged: widget.task != null
                  ? null
                  : (value) {
                      if (value != null) setState(() => _projectId = value);
                    },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('taskAgentField'),
              initialValue: _agentId,
              decoration: const InputDecoration(labelText: 'ИИ-агент'),
              items: widget.repository.agents
                  .map((agent) => DropdownMenuItem(
                        value: agent.id,
                        child: Text(agent.name),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _agentId = value);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('taskTitleField'),
              controller: _title,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Название задачи'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveTaskButton'),
            onPressed: () {
              final title = _title.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(
                context,
                (
                  projectId: _projectId,
                  agentId: _agentId,
                  title: title,
                ),
              );
            },
            child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
          ),
        ],
      );
}

class _WorkingMemoryDialog extends StatefulWidget {
  const _WorkingMemoryDialog({
    required this.task,
    required this.initialContent,
  });
  final AgentTask task;
  final String initialContent;

  @override
  State<_WorkingMemoryDialog> createState() => _WorkingMemoryDialogState();
}

class _WorkingMemoryDialogState extends State<_WorkingMemoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Рабочая память · ${widget.task.title}'),
        content: SizedBox(
          width: 540,
          child: TextField(
            key: const Key('taskMemoryField'),
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 12,
            maxLength: 24000,
            decoration: const InputDecoration(
              labelText: 'Цель, ограничение или состояние задачи',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveTaskMemoryButton'),
            onPressed: () {
              Navigator.pop(context, _controller.text.trim());
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
