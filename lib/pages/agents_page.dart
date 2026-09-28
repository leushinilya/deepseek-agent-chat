import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({
    required this.repository,
    this.ragClient,
    super.key,
  });

  final AgentChatRepository repository;
  final http.Client? ragClient;

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
              if (agent.ragIds.isNotEmpty) ...[
                const SizedBox(height: 6),
                Chip(
                  avatar: const Icon(Icons.menu_book_outlined),
                  label: Text('RAG: ${agent.ragIds.length}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (agent.mcpServers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final server in agent.mcpServers)
                      Chip(
                        key: Key('agentMcp-${agent.id}-${server.id}'),
                        avatar: Icon(server.type == 'fetch'
                            ? Icons.language
                            : Icons.folder_outlined),
                        label: Text(server.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                const Text('MCP не подключены',
                    style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12)),
              ],
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
      builder: (_) => _AgentDialog(
        agent: agent,
        availableMcpServers: repository.mcpServers,
        ragClient: ragClient,
      ),
    );
    if (result == null) return;
    if (agent == null) {
      repository.createAgent(
        name: result.name,
        systemPrompt: result.systemPrompt,
        model: result.model,
        mcpServers: result.mcpServers,
        ragIds: result.ragIds,
      );
    } else {
      repository.updateAgent(agent.copyWith(
        name: result.name,
        systemPrompt: result.systemPrompt,
        model: result.model,
        mcpServers: result.mcpServers,
        ragIds: result.ragIds,
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
  const _AgentDraft(
      this.name, this.systemPrompt, this.model, this.mcpServers, this.ragIds);
  final String name;
  final String systemPrompt;
  final AgentModel model;
  final List<McpServer> mcpServers;
  final List<String> ragIds;
}

class _SelectionOption {
  const _SelectionOption(this.id, this.label,
      {this.detail, this.enabled = true});
  final String id;
  final String label;
  final String? detail;
  final bool enabled;
}

class _AgentDialog extends StatefulWidget {
  const _AgentDialog(
      {this.agent, required this.availableMcpServers, this.ragClient});
  final AiAgent? agent;
  final List<McpServer> availableMcpServers;
  final http.Client? ragClient;

  @override
  State<_AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends State<_AgentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.agent?.name);
  late final _prompt = TextEditingController(text: widget.agent?.systemPrompt);
  late var _model = widget.agent?.model ?? AgentModel.localGigaChat;
  late final Set<String> _selectedMcpIds =
      widget.agent?.mcpServers.map((server) => server.id).toSet() ?? {};
  late final Set<String> _selectedRagIds = widget.agent?.ragIds.toSet() ?? {};
  List<Map<String, dynamic>> _rags = [];
  bool _loadingRags = true;
  String? _ragError;

  @override
  void initState() {
    super.initState();
    _loadRags();
  }

  Future<void> _loadRags() async {
    const baseUrl = String.fromEnvironment('API_BASE_URL',
        defaultValue: 'http://localhost:3000');
    final client = widget.ragClient ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/api/rags'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw const FormatException();
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(
          () => _rags = (payload['rags'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) {
        setState(() => _ragError = 'Не удалось загрузить список RAG.');
      }
    } finally {
      if (mounted) setState(() => _loadingRags = false);
      if (widget.ragClient == null) client.close();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  List<_SelectionOption> get _mcpOptions => [
        for (final server in widget.availableMcpServers)
          _SelectionOption(
              server.id,
              server.type == 'fetch'
                  ? server.name
                  : '${server.name}: ${server.directories.join(', ')}',
              detail: server.type == 'fetch'
                  ? 'Чтение веб-страниц'
                  : server.directories.join(', ')),
      ];

  List<_SelectionOption> get _ragOptions => [
        for (final rag in _rags)
          _SelectionOption(rag['id'] as String, rag['name'] as String,
              detail: rag['status'] == 'indexed'
                  ? '${rag['documentCount'] ?? 0} документов'
                  : 'Ожидает индексации',
              enabled: rag['status'] == 'indexed'),
        for (final id in _selectedRagIds)
          if (!_rags.any((rag) => rag['id'] == id))
            _SelectionOption(id, 'Недоступный RAG ($id)', enabled: false),
      ];

  Widget _selectionButton({
    required String label,
    required String keyName,
    required String optionKeyPrefix,
    required List<_SelectionOption> options,
    required Set<String> selected,
    required String emptyMessage,
    int? maxSelected,
  }) {
    final names = options
        .where((option) => selected.contains(option.id))
        .map((option) => option.label)
        .toList();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: Key(keyName),
        onPressed: () => _chooseOptions(
            label: label,
            optionKeyPrefix: optionKeyPrefix,
            options: options,
            selected: selected,
            emptyMessage: emptyMessage,
            maxSelected: maxSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(names.isEmpty ? 'Ничего не выбрано' : names.join(', '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
            ),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      ),
    );
  }

  Future<void> _chooseOptions({
    required String label,
    required String optionKeyPrefix,
    required List<_SelectionOption> options,
    required Set<String> selected,
    required String emptyMessage,
    int? maxSelected,
  }) async {
    final draft = {...selected};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 480,
            height: options.isEmpty
                ? 90
                : (options.length * 74.0).clamp(90.0, 400.0),
            child: options.isEmpty
                ? Center(child: Text(emptyMessage))
                : ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final checked = draft.contains(option.id);
                      return CheckboxListTile(
                        key: Key('$optionKeyPrefix-${option.id}'),
                        value: checked,
                        title: Text(option.label),
                        subtitle:
                            option.detail == null ? null : Text(option.detail!),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (!option.enabled && !checked) ||
                                (!checked &&
                                    maxSelected != null &&
                                    draft.length >= maxSelected)
                            ? null
                            : (value) => update(() {
                                  if (value == true) {
                                    draft.add(option.id);
                                  } else {
                                    draft.remove(option.id);
                                  }
                                }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, draft),
                child: const Text('Готово')),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        selected
          ..clear()
          ..addAll(result);
      });
    }
  }

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
                const SizedBox(height: 18),
                _selectionButton(
                  label: 'RAG',
                  keyName: 'agentRagButton',
                  optionKeyPrefix: 'agentRagSelection',
                  options: _ragOptions,
                  selected: _selectedRagIds,
                  emptyMessage: 'Сначала создайте RAG в настройках.',
                ),
                if (_loadingRags) const LinearProgressIndicator(),
                if (_ragError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_ragError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                if (!_loadingRags && _rags.isEmpty && _ragError == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Сначала создайте и проиндексируйте RAG в настройках.'),
                  ),
                const SizedBox(height: 18),
                _selectionButton(
                  label: 'MCP-серверы',
                  keyName: 'agentMcpButton',
                  optionKeyPrefix: 'agentMcpSelection',
                  options: _mcpOptions,
                  selected: _selectedMcpIds,
                  emptyMessage: 'Сначала создайте MCP в настройках.',
                  maxSelected: 5,
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
              Navigator.pop(
                  context,
                  _AgentDraft(
                    _name.text.trim(),
                    _prompt.text.trim(),
                    _model,
                    widget.availableMcpServers
                        .where((server) => _selectedMcpIds.contains(server.id))
                        .toList(growable: false),
                    _selectedRagIds.toList(growable: false),
                  ));
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
