import 'package:flutter/material.dart';

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';

class StateModelsPage extends StatelessWidget {
  const StateModelsPage({required this.repository, super.key});

  final AgentChatRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) => Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('createStateModelButton'),
            onPressed: () => _createModel(context),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Новая модель'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
                child: repository.stateModels.isEmpty
                    ? const Center(
                        child: Text('Создайте модель и добавьте состояния.'),
                      )
                    : ListView.separated(
                        itemCount: repository.stateModels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) =>
                            _modelCard(context, repository.stateModels[index]),
                      ),
              ),
            ),
          ),
        ),
      );

  Widget _modelCard(BuildContext context, TaskStateModel model) => AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(model.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                key: Key('deleteStateModel-${model.id}'),
                tooltip: 'Удалить модель',
                onPressed: () {
                  try {
                    repository.deleteStateModel(model.id);
                  } on StateError {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Модель назначена проекту.')));
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ]),
            const SizedBox(height: 6),
            if (model.states.isEmpty)
              const Text('Состояний пока нет.',
                  style: TextStyle(color: Color(0xFF667085)))
            else
              for (var index = 0; index < model.states.length; index++)
                _stateRow(model, model.states[index], index),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: Key('addState-${model.id}'),
                onPressed: () => _addState(context, model),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить состояние'),
              ),
            ),
          ],
        ),
      );

  Widget _stateRow(
    TaskStateModel model,
    TaskStateDefinition state,
    int index,
  ) =>
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color(state.colorValue).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(state.colorValue)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Color(state.colorValue),
            foregroundColor: Colors.white,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(state.description,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF475467))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Выше',
            onPressed: index == 0
                ? null
                : () => repository.moveState(model.id, state.id, -1),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
          IconButton(
            tooltip: 'Ниже',
            onPressed: index == model.states.length - 1
                ? null
                : () => repository.moveState(model.id, state.id, 1),
            icon: const Icon(Icons.arrow_downward_rounded),
          ),
        ]),
      );

  Future<void> _createModel(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (title != null) repository.createStateModel(title: title);
  }

  Future<void> _addState(BuildContext context, TaskStateModel model) async {
    final value = await showDialog<_StateInput>(
      context: context,
      builder: (_) => _StateDialog(modelTitle: model.title),
    );
    if (value == null) return;
    repository.addStateToModel(
      model.id,
      name: value.name,
      description: value.description,
      colorValue: value.colorValue,
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Новая модель состояний'),
        content: TextField(
          key: const Key('stateModelTitleField'),
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveStateModelButton'),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Создать'),
          ),
        ],
      );
}

class _StateInput {
  const _StateInput(this.name, this.description, this.colorValue);
  final String name;
  final String description;
  final int colorValue;
}

class _StateDialog extends StatefulWidget {
  const _StateDialog({required this.modelTitle});
  final String modelTitle;

  @override
  State<_StateDialog> createState() => _StateDialogState();
}

class _StateDialogState extends State<_StateDialog> {
  static const colors = [
    0xFF3659D9,
    0xFF7F56D9,
    0xFF039855,
    0xFFF79009,
    0xFFD92D20,
    0xFF0891B2,
  ];
  final name = TextEditingController();
  final description = TextEditingController();
  int colorValue = colors.first;

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Состояние · ${widget.modelTitle}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('stateNameField'),
              controller: name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              key: const Key('stateDescriptionField'),
              controller: description,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Описание и инструкции для LLM',
                alignLabelWithHint: true,
              ),
            ),
            Wrap(
              spacing: 10,
              children: colors
                  .map((value) => InkWell(
                        key: Key('stateColor-$value'),
                        onTap: () => setState(() => colorValue = value),
                        borderRadius: BorderRadius.circular(99),
                        child: CircleAvatar(
                          backgroundColor: Color(value),
                          child: value == colorValue
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('saveStateButton'),
            onPressed: () {
              final cleanName = name.text.trim();
              final cleanDescription = description.text.trim();
              if (cleanName.isEmpty || cleanDescription.isEmpty) return;
              Navigator.pop(context,
                  _StateInput(cleanName, cleanDescription, colorValue));
            },
            child: const Text('Добавить'),
          ),
        ],
      );
}
