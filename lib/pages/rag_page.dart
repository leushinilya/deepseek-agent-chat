import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../agents/repository.dart';
import '../widgets/app_surface.dart';
import 'rag_document.dart';
import 'rag_document_picker.dart';
import 'rag_index_dialog.dart';

class RagPage extends StatefulWidget {
  const RagPage({this.client, this.repository, super.key});

  final http.Client? client;
  final AgentChatRepository? repository;

  @override
  State<RagPage> createState() => _RagPageState();
}

class _RagPageState extends State<RagPage> {
  static const _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:3000');
  late final http.Client _client = widget.client ?? http.Client();
  List<Map<String, dynamic>> _rags = [];
  Map<String, dynamic>? _selected;
  String _strategy = 'fixed';
  String? _error;
  bool _busy = false;
  Timer? _poll;
  StateSetter? _updateDetailsDialog;

  void _update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _updateDetailsDialog?.call(() {});
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_selected?['status'] == 'indexing') _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<dynamic> _request(String path,
      {Object? body, String method = 'POST'}) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final response = method == 'DELETE'
          ? await _client.delete(uri)
          : body == null
              ? await _client.get(uri)
              : await (method == 'PATCH' ? _client.patch : _client.post)(uri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body));
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(payload is Map ? payload['error'] : 'Ошибка сервера.');
      }
      return payload;
    } catch (error) {
      if (error is Exception && error.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception('Не удалось связаться с сервером RAG.');
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final payload = await _request('/api/rags') as Map<String, dynamic>;
      final rags = (payload['rags'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? selected;
      if (_selected != null) {
        final id = _selected!['id'];
        if (rags.any((rag) => rag['id'] == id)) {
          selected = await _request('/api/rags/$id') as Map<String, dynamic>;
        }
      }
      if (!mounted) return;
      _update(() {
        _rags = rags;
        _selected = selected;
        _error = null;
      });
    } catch (error) {
      if (!silent) _update(() => _error = _message(error));
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _create() async {
    final controller = TextEditingController();
    List<RagDocumentFile> documents = [];
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Добавить RAG'),
          content: SizedBox(
            width: 480,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('ragNameField'),
                    controller: controller,
                    maxLength: 120,
                    decoration:
                        const InputDecoration(labelText: 'Название RAG'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('ragChooseDocumentsButton'),
                    onPressed: () async {
                      try {
                        final chosen = await pickRagDocuments();
                        update(() {
                          documents = chosen;
                          error = null;
                        });
                      } catch (cause) {
                        update(() => error = _message(cause));
                      }
                    },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Выбрать документы'),
                  ),
                  if (documents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(documents.length <= 5
                          ? documents.map((file) => file.name).join(', ')
                          : '${documents.length} документов: ${documents.take(5).map((file) => file.name).join(', ')}…'),
                    ),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('ragCreateButton'),
              onPressed: () {
                if (controller.text.trim().isEmpty || documents.isEmpty) {
                  update(
                      () => error = 'Укажите название и выберите документы.');
                  return;
                }
                Navigator.pop(context,
                    {'name': controller.text.trim(), 'documents': documents});
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    String? createdId;
    await _run(() async {
      _selected = await uploadRagDocuments(
          _baseUrl, '/api/rags', result['documents'] as List<RagDocumentFile>,
          name: result['name'] as String);
      createdId = _selected!['id'] as String;
      await _refresh();
    });
    if (createdId != null && mounted) await _openDetails();
  }

  Future<void> _addDocuments() async {
    final id = _selected?['id'];
    if (id == null) return;
    try {
      final documents = await pickRagDocuments();
      if (documents.isEmpty) return;
      await _run(() async {
        _selected = await uploadRagDocuments(
            _baseUrl, '/api/rags/$id/documents', documents);
        await _refresh();
      });
    } catch (error) {
      _update(() => _error = _message(error));
    }
  }

  Future<void> _index() async {
    final id = _selected?['id'];
    if (id == null) return;
    await _run(() async {
      _selected =
          await _request('/api/rags/$id/index', body: {'strategy': _strategy})
              as Map<String, dynamic>;
      await _refresh();
    });
  }

  Future<void> _rename() async {
    final rag = _selected;
    if (rag == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameRagDialog(initialName: rag['name'] as String),
    );
    if (name == null || name == rag['name']) return;
    await _run(() async {
      _selected = await _request('/api/rags/${rag['id']}',
          body: {'name': name}, method: 'PATCH') as Map<String, dynamic>;
      await _refresh();
    });
  }

  Future<void> _delete(Map<String, dynamic> rag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить RAG?'),
        content:
            Text('«${rag['name']}» и его документы с индексом будут удалены. '
                'RAG также будет отключён от агентов.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('ragConfirmDeleteButton'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var removed = false;
    await _run(() async {
      await _request('/api/rags/${rag['id']}', method: 'DELETE');
      for (final agent in widget.repository?.agents ?? []) {
        if (agent.ragIds.contains(rag['id'])) {
          widget.repository!.updateAgent(agent.copyWith(
            ragIds: agent.ragIds.where((id) => id != rag['id']).toList(),
          ));
        }
      }
      removed = true;
    });
    if (!removed || !mounted) return;
    if (_selected?['id'] == rag['id']) {
      Navigator.of(context).pop();
      _updateDetailsDialog = null;
      _selected = null;
    }
    await _refresh();
  }

  void _checkIndex() {
    final rag = _selected;
    if (rag == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => RagIndexDialog(
        ragId: rag['id'] as String,
        ragName: rag['name'] as String,
        client: _client,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _update(() => _error = _message(error));
    } finally {
      _update(() => _busy = false);
    }
  }

  Future<void> _select(String id) async {
    await _run(() async {
      final rag = await _request('/api/rags/$id') as Map<String, dynamic>;
      _update(() {
        _selected = rag;
        _strategy = rag['strategy'] == 'structure' ? 'structure' : 'fixed';
      });
    });
    if (mounted && _selected?['id'] == id) await _openDetails();
  }

  Future<void> _openDetails() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          _updateDetailsDialog = update;
          return AlertDialog(
            key: const Key('ragDetailsDialog'),
            title: const Text('Карточка RAG'),
            content: SizedBox(
              width: 680,
              height: MediaQuery.sizeOf(context).height * 0.68,
              child: SingleChildScrollView(
                child: _selected == null
                    ? const Text('RAG не найден.')
                    : _buildDetails(context),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    );
    _updateDetailsDialog = null;
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('RAG',
                        style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  FilledButton.icon(
                    key: const Key('addRagButton'),
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить RAG'),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                    'Выберите RAG, чтобы открыть документы и настройки индексации.'),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                Text('Добавленные RAG',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (_rags.isEmpty)
                  const AppSurface(
                    child:
                        Text('Пока нет RAG. Добавьте первый набор документов.'),
                  ),
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth >= 650
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final rag in _rags)
                        SizedBox(width: width, child: _ragCard(context, rag)),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );

  Widget _ragCard(BuildContext context, Map<String, dynamic> rag) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E6EF)),
        ),
        child: InkWell(
          key: Key('rag-${rag['id']}'),
          borderRadius: BorderRadius.circular(20),
          onTap: _busy ? null : () => _select(rag['id'] as String),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.library_books_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(rag['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    key: Key('ragDelete-${rag['id']}'),
                    tooltip: 'Удалить RAG',
                    onPressed: _busy || rag['status'] == 'indexing'
                        ? null
                        : () => _delete(rag),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height: 14),
                Text(
                    '${rag['documentCount']} документов · ${rag['chunkCount']} чанков'),
                const SizedBox(height: 6),
                Text(_status(rag['status'])),
              ],
            ),
          ),
        ),
      );

  Widget _buildDetails(BuildContext context) {
    final rag = _selected!;
    final documents = rag['documents'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(rag['name'] as String,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            key: const Key('ragRenameButton'),
            tooltip: 'Переименовать RAG',
            onPressed: _busy ? null : _rename,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: const Key('ragDeleteButton'),
            tooltip: 'Удалить RAG',
            onPressed: _busy || rag['status'] == 'indexing'
                ? null
                : () => _delete(rag),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        for (final document in documents)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text(document['name'] as String),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('ragAddDocumentsButton'),
            onPressed:
                _busy || rag['status'] == 'indexing' ? null : _addDocuments,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Добавить документы'),
          ),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: const Key('ragChunkStrategy'),
          initialValue: _strategy,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Стратегия разбиения'),
          items: const [
            DropdownMenuItem(
                value: 'fixed',
                child: Text('По фиксированному размеру',
                    overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(
                value: 'structure',
                child: Text('По структуре (заголовки, разделы, файлы)',
                    overflow: TextOverflow.ellipsis)),
          ],
          onChanged: rag['status'] == 'indexing'
              ? null
              : (value) {
                  if (value != null) _update(() => _strategy = value);
                },
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('ragCheckButton'),
              onPressed: _checkIndex,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Проверка'),
            ),
            FilledButton.icon(
              key: const Key('ragIndexButton'),
              onPressed: _busy || rag['status'] == 'indexing' ? null : _index,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Запустить индексацию'),
            ),
          ],
        ),
        if (rag['status'] == 'indexing')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (rag['status'] == 'error')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(rag['error'] as String? ?? 'Ошибка индексации.',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (rag['status'] == 'indexed')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                'Индекс готов: ${rag['chunkCount']} чанков сохранено в SQLite.'),
          ),
      ],
    );
  }

  String _status(Object? status) => switch (status) {
        'indexing' => 'индексируется',
        'indexed' => 'индекс готов',
        'error' => 'ошибка',
        _ => 'ожидает индексации',
      };
}

class _RenameRagDialog extends StatefulWidget {
  const _RenameRagDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameRagDialog> createState() => _RenameRagDialogState();
}

class _RenameRagDialogState extends State<_RenameRagDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Переименовать RAG'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('ragRenameField'),
              controller: _controller,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('ragRenameSaveButton'),
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isEmpty) {
                setState(() => _error = 'Укажите название RAG.');
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
