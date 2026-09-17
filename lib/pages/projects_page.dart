import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({required this.repository, super.key});

  final AgentChatRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) => Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('createProjectButton'),
            onPressed: () => _create(context),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Новый проект'),
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
                      Text('Проекты',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text(
                        'Проект объединяет задачи и хранит долговременную память.',
                        style: TextStyle(color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 22),
                      if (repository.projects.isEmpty)
                        Expanded(child: _empty(context))
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: repository.projects.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _card(context, repository.projects[index]),
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
            const Icon(Icons.folder_outlined,
                size: 48, color: Color(0xFF7A8496)),
            const SizedBox(height: 14),
            Text('Проектов пока нет',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Создайте проект — ему не нужно выбирать владельца.',
                style: TextStyle(color: Color(0xFF667085))),
          ]),
        ),
      );

  Widget _card(BuildContext context, AgentProject project) {
    final items = repository.longTermMemory(project.id).items;
    final stateModel = repository.stateModelById(project.stateModelId);
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.folder_outlined, color: Color(0xFF3659D9)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              Text('задач: ${repository.taskCountForProject(project.id)}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF667085))),
            ]),
          ),
          IconButton(
            key: Key('addLongTermMemory-${project.id}'),
            tooltip: 'Добавить запись долговременной памяти',
            onPressed: () => _addMemory(context, project),
            icon: const Icon(Icons.psychology_alt_outlined),
          ),
          IconButton(
            key: Key('addInvariant-${project.id}'),
            tooltip: 'Добавить инвариант',
            onPressed: () => _addInvariant(context, project),
            icon: const Icon(Icons.gpp_maybe_outlined),
          ),
          IconButton(
            key: Key('deleteProject-${project.id}'),
            tooltip: 'Удалить проект',
            onPressed: () => _delete(context, project),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: Key('projectStateModel-${project.id}'),
          initialValue: stateModel?.id,
          decoration: const InputDecoration(
            labelText: 'Модель состояний',
            helperText: 'При смене модели прогресс этапов задач сбрасывается.',
          ),
          hint: const Text('Не назначена'),
          items: repository.stateModels
              .map((model) => DropdownMenuItem(
                    value: model.id,
                    child: Text(model.title),
                  ))
              .toList(),
          onChanged: repository.stateModels.isEmpty
              ? null
              : (value) {
                  if (value != null && value != project.stateModelId) {
                    repository.assignStateModelToProject(project.id, value);
                  }
                },
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.gpp_maybe_outlined,
              size: 18, color: Color(0xFFD92D20)),
          const SizedBox(width: 8),
          Text('Инварианты', style: Theme.of(context).textTheme.titleSmall),
        ]),
        const SizedBox(height: 6),
        if (project.invariants.isEmpty)
          const Text('Запреты для агента не заданы.',
              style: TextStyle(
                  color: Color(0xFF667085), fontStyle: FontStyle.italic))
        else
          ...project.invariants.map((invariant) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(invariant.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text(invariant.description,
                                  style: const TextStyle(
                                      color: Color(0xFF475467))),
                            ]),
                      ),
                      IconButton(
                        key: Key('deleteInvariant-${invariant.id}'),
                        tooltip: 'Удалить инвариант',
                        onPressed: () => repository.deleteProjectInvariant(
                            project.id, invariant.id),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ]),
              )),
        const SizedBox(height: 12),
        Text('Долговременная память',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Text('Долговременная память проекта пуста.',
              style: TextStyle(
                  color: Color(0xFF667085), fontStyle: FontStyle.italic))
        else
          ...items.map((item) => Row(children: [
                Expanded(child: Text(item.content)),
                IconButton(
                  key: Key('deleteLongTermMemory-${item.id}'),
                  tooltip: 'Удалить из долговременной памяти',
                  onPressed: () =>
                      repository.deleteLongTermMemoryItem(project.id, item.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ])),
      ]),
    );
  }

  Future<void> _create(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const _ProjectTextDialog(
        title: 'Новый проект',
        label: 'Название проекта',
        fieldKey: Key('projectTitleField'),
        saveKey: Key('saveProjectButton'),
        saveLabel: 'Создать',
      ),
    );
    if (title != null) repository.createProject(title: title);
  }

  Future<void> _addMemory(BuildContext context, AgentProject project) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectTextDialog(
        title: 'Память · ${project.title}',
        label: 'Профиль, решение или знание',
        fieldKey: const Key('projectMemoryField'),
        saveKey: const Key('saveProjectMemoryButton'),
        saveLabel: 'Добавить',
        memory: true,
      ),
    );
    if (value != null) repository.rememberLongTerm(project.id, value);
  }

  Future<void> _addInvariant(BuildContext context, AgentProject project) async {
    final draft = await showDialog<_InvariantDraft>(
      context: context,
      builder: (context) => _InvariantDialog(projectTitle: project.title),
    );
    if (draft != null) {
      repository.addProjectInvariant(
        project.id,
        name: draft.name,
        description: draft.description,
      );
    }
  }

  Future<void> _delete(BuildContext context, AgentProject project) async {
    final count = repository.taskCountForProject(project.id);
    if (count > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Нельзя удалить проект'),
          content:
              Text('С проектом связаны задачи: $count. Сначала удалите их.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Понятно')),
          ],
        ),
      );
      return;
    }
    repository.deleteProject(project.id);
  }
}

class _InvariantDraft {
  const _InvariantDraft(this.name, this.description);
  final String name;
  final String description;
}

class _InvariantDialog extends StatefulWidget {
  const _InvariantDialog({required this.projectTitle});
  final String projectTitle;

  @override
  State<_InvariantDialog> createState() => _InvariantDialogState();
}

class _InvariantDialogState extends State<_InvariantDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Инвариант · ${widget.projectTitle}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('invariantNameField'),
              controller: _name,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('invariantDescriptionField'),
              controller: _description,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Описание запрета',
                helperText: 'Что агент не имеет права делать или нарушать.',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveInvariantButton'),
            onPressed: () {
              final name = _name.text.trim();
              final description = _description.text.trim();
              if (name.isNotEmpty && description.isNotEmpty) {
                Navigator.pop(context, _InvariantDraft(name, description));
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      );
}

class _ProjectTextDialog extends StatefulWidget {
  const _ProjectTextDialog({
    required this.title,
    required this.label,
    required this.fieldKey,
    required this.saveKey,
    required this.saveLabel,
    this.memory = false,
  });

  final String title;
  final String label;
  final Key fieldKey;
  final Key saveKey;
  final String saveLabel;
  final bool memory;

  @override
  State<_ProjectTextDialog> createState() => _ProjectTextDialogState();
}

class _ProjectTextDialogState extends State<_ProjectTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: true,
          minLines: widget.memory ? 3 : 1,
          maxLines: widget.memory ? 6 : 1,
          maxLength: widget.memory ? 4000 : 200,
          decoration: InputDecoration(labelText: widget.label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: widget.saveKey,
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(widget.saveLabel),
          ),
        ],
      );
}
