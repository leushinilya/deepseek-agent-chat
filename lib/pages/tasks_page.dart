import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';

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
    final items = repository.workingMemory(task.id).items;
    final chatCount = repository.chatCountForTask(task.id);
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
                    '${project?.title ?? 'Проект недоступен'} · чатов: $chatCount',
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('addWorkingMemory-${task.id}'),
              tooltip: 'Добавить запись рабочей памяти',
              onPressed: () => _addMemory(context, task),
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              key: Key('deleteTask-${task.id}'),
              tooltip: 'Удалить задачу',
              onPressed: () => _deleteTask(context, task),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ]),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text('Рабочая память задачи пуста.',
                style: TextStyle(
                    color: Color(0xFF667085), fontStyle: FontStyle.italic))
          else
            ...items.map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                        left: BorderSide(color: Color(0xFF3659D9), width: 3)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(item.content)),
                    IconButton(
                      key: Key('deleteWorkingMemory-${item.id}'),
                      tooltip: 'Удалить из рабочей памяти',
                      onPressed: () =>
                          repository.deleteWorkingMemoryItem(task.id, item.id),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ]),
                )),
        ],
      ),
    );
  }

  Future<void> _createTask(BuildContext context) async {
    if (repository.projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала создайте проект.')));
      return;
    }
    final result = await showDialog<({String projectId, String title})>(
      context: context,
      builder: (_) => _CreateTaskDialog(repository: repository),
    );
    if (result != null) {
      repository.createTask(projectId: result.projectId, title: result.title);
    }
  }

  Future<void> _addMemory(BuildContext context, AgentTask task) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _WorkingMemoryDialog(task: task),
    );
    if (value != null) repository.rememberWorking(task.id, value);
  }

  Future<void> _deleteTask(BuildContext context, AgentTask task) async {
    final chatCount = repository.chatCountForTask(task.id);
    if (chatCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Нельзя удалить задачу'),
          content: Text(
              'С задачей связаны чаты: $chatCount. Сначала удалите эти чаты.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Понятно')),
          ],
        ),
      );
      return;
    }
    repository.deleteTask(task.id);
  }
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({required this.repository});
  final AgentChatRepository repository;

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  late String _projectId = widget.repository.projects.first.id;
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Новая задача'),
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
              onChanged: (value) {
                if (value != null) setState(() => _projectId = value);
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
              Navigator.pop(context, (projectId: _projectId, title: title));
            },
            child: const Text('Создать'),
          ),
        ],
      );
}

class _WorkingMemoryDialog extends StatefulWidget {
  const _WorkingMemoryDialog({required this.task});
  final AgentTask task;

  @override
  State<_WorkingMemoryDialog> createState() => _WorkingMemoryDialogState();
}

class _WorkingMemoryDialogState extends State<_WorkingMemoryDialog> {
  final _controller = TextEditingController();

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
            maxLines: 6,
            maxLength: 4000,
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
              final text = _controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Добавить'),
          ),
        ],
      );
}
