import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';
import 'tasks_page.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({required this.repository, this.onOpenTasks, super.key});

  final AgentChatRepository repository;
  final ValueChanged<String>? onOpenTasks;

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
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
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
                            padding: const EdgeInsets.only(bottom: 96),
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
    final memory = repository.longTermMemory(project.id).content;
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
            key: Key('deleteProject-${project.id}'),
            tooltip: 'Удалить проект',
            onPressed: () => _delete(context, project),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ]),
        const SizedBox(height: 12),
        _editableArea(
          context,
          title: 'Модель состояний',
          text: stateModel?.title ?? 'Не назначена',
          actionKey: Key('projectStateModel-${project.id}'),
          onPressed: () => _selectStateModel(context, project),
        ),
        const SizedBox(height: 12),
        _editableArea(
          context,
          title: 'Инварианты',
          text: project.invariants.isEmpty
              ? 'Запреты для агента не заданы.'
              : project.invariants
                  .map((item) => '${item.name}\n${item.description}')
                  .join('\n\n'),
          actionKey: Key('editInvariants-${project.id}'),
          onPressed: () => _editInvariants(context, project),
        ),
        const SizedBox(height: 12),
        _editableArea(
          context,
          title: 'Долговременная память',
          text:
              memory.isEmpty ? 'Долговременная память проекта пуста.' : memory,
          actionKey: Key('editLongTermMemory-${project.id}'),
          onPressed: () => _editMemory(context, project),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: Key('projectTasks-${project.id}'),
          onPressed: () {
            if (onOpenTasks != null) {
              onOpenTasks!(project.id);
            } else {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Задачи · ${project.title}')),
                  body: TasksPage(
                    repository: repository,
                    initialProjectId: project.id,
                  ),
                ),
              ));
            }
          },
          icon: const Icon(Icons.task_alt_outlined),
          label: Text(
              'Задачи проекта (${repository.taskCountForProject(project.id)})'),
        ),
      ]),
    );
  }

  Widget _editableArea(
    BuildContext context, {
    required String title,
    required String text,
    required Key actionKey,
    required VoidCallback onPressed,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E6EF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SelectableText(text,
                      style: const TextStyle(color: Color(0xFF475467))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: actionKey,
              tooltip: 'Редактировать: $title',
              onPressed: onPressed,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      );

  Future<void> _editInvariants(BuildContext context, AgentProject project) =>
      showDialog<void>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: repository,
          builder: (context, _) {
            final invariants =
                repository.projectById(project.id)?.invariants ?? [];
            return AlertDialog(
              title: Text('Инварианты · ${project.title}'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (invariants.isEmpty)
                      const Text('Запреты для агента не заданы.'),
                    ...invariants.map((item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          subtitle: Text(item.description),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              key: Key('editInvariant-${item.id}'),
                              tooltip: 'Редактировать инвариант',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  _editInvariant(context, project, item),
                            ),
                            IconButton(
                              key: Key('deleteInvariant-${item.id}'),
                              tooltip: 'Удалить инвариант',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => repository
                                  .deleteProjectInvariant(project.id, item.id),
                            ),
                          ]),
                        )),
                  ]),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Готово')),
                FilledButton.icon(
                  key: Key('addInvariant-${project.id}'),
                  onPressed: () => _addInvariant(context, project),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            );
          },
        ),
      );

  Future<void> _editInvariant(BuildContext context, AgentProject project,
      ProjectInvariant invariant) async {
    final draft = await showDialog<_InvariantDraft>(
      context: context,
      builder: (_) =>
          _InvariantDialog(projectTitle: project.title, invariant: invariant),
    );
    if (draft != null) {
      repository.updateProjectInvariant(project.id, invariant.id,
          name: draft.name, description: draft.description);
    }
  }

  Future<void> _selectStateModel(
      BuildContext context, AgentProject project) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Модель состояний'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('При смене модели прогресс этапов задач сбрасывается.'),
          ),
          if (repository.stateModels.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Сначала создайте модель состояний в настройках.'),
            ),
          ...repository.stateModels.map((model) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, model.id),
                child: Row(children: [
                  Expanded(child: Text(model.title)),
                  if (model.id == project.stateModelId)
                    const Icon(Icons.check, size: 18),
                ]),
              )),
        ],
      ),
    );
    if (selected != null && selected != project.stateModelId) {
      repository.assignStateModelToProject(project.id, selected);
    }
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

  Future<void> _editMemory(BuildContext context, AgentProject project) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectTextDialog(
        title: 'Память · ${project.title}',
        label: 'Промпт долговременной памяти',
        initialContent: repository.longTermMemory(project.id).content,
        fieldKey: const Key('projectMemoryField'),
        saveKey: const Key('saveProjectMemoryButton'),
        saveLabel: 'Сохранить',
        memory: true,
      ),
    );
    if (value != null) repository.updateLongTermMemory(project.id, value);
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
  const _InvariantDialog({required this.projectTitle, this.invariant});
  final String projectTitle;
  final ProjectInvariant? invariant;

  @override
  State<_InvariantDialog> createState() => _InvariantDialogState();
}

class _InvariantDialogState extends State<_InvariantDialog> {
  late final _name = TextEditingController(text: widget.invariant?.name);
  late final _description =
      TextEditingController(text: widget.invariant?.description);

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
            child: Text(widget.invariant == null ? 'Добавить' : 'Сохранить'),
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
    this.initialContent = '',
  });

  final String title;
  final String label;
  final Key fieldKey;
  final Key saveKey;
  final String saveLabel;
  final bool memory;
  final String initialContent;

  @override
  State<_ProjectTextDialog> createState() => _ProjectTextDialogState();
}

class _ProjectTextDialogState extends State<_ProjectTextDialog> {
  late final _controller = TextEditingController(text: widget.initialContent);

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
          maxLength: widget.memory ? 500000 : 200,
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
              if (widget.memory || value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
            child: Text(widget.saveLabel),
          ),
        ],
      );
}
