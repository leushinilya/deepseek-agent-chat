import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../agents/models.dart';
import '../agents/repository.dart';
import '../widgets/app_surface.dart';
import 'mcp_directory_picker.dart';
import 'mcp_tools_dialog.dart';

class McpPage extends StatelessWidget {
  const McpPage({required this.repository, super.key});

  final AgentChatRepository repository;

  Future<void> _add(BuildContext context, [McpServer? existingServer]) async {
    final controller =
        TextEditingController(text: existingServer?.directories.join('\n'));
    var serverType = existingServer?.type ?? 'filesystem';
    String? error;
    var checking = false;
    final result = await showDialog<({String type, List<String> directories})>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: Text(existingServer == null
                    ? 'Добавить MCP'
                    : 'Редактировать MCP'),
                content: SizedBox(
                  width: 520,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (existingServer == null)
                      DropdownButtonFormField<String>(
                        key: const Key('mcpTypeField'),
                        initialValue: serverType,
                        decoration: const InputDecoration(labelText: 'Тип MCP'),
                        items: const [
                          DropdownMenuItem(
                              value: 'filesystem',
                              child: Text('Файловая система')),
                          DropdownMenuItem(
                              value: 'fetch', child: Text('Чтение сайтов')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => serverType = value);
                        },
                      ),
                    if (serverType == 'filesystem') const SizedBox(height: 16),
                    if (serverType == 'filesystem')
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: TextField(
                              key: const Key('mcpDirectoriesField'),
                              controller: controller,
                              minLines: 2,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText:
                                    'Каталоги на машине backend',
                                hintText: '/absolute/path/to/project',
                                helperText:
                                    'MCP получит доступ только к этим папкам',
                                border: OutlineInputBorder(),
                              ),
                            )),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              key: const Key('browseMcpDirectoryButton'),
                              tooltip: 'Выбрать каталог',
                              icon: const Icon(Icons.folder_open_outlined),
                              onPressed: () async {
                                final path = await showDialog<String>(
                                  context: context,
                                  builder: (_) => const McpDirectoryPicker(),
                                );
                                if (path == null) return;
                                final existing = controller.text.trim();
                                controller.text = existing.isEmpty
                                    ? path
                                    : '$existing\n$path';
                                setState(() => error = null);
                              },
                            ),
                          ]),
                    if (serverType == 'fetch')
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'Агент сможет читать веб-страницы по URL из запроса.')),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  FilledButton(
                    key: const Key('saveMcpServerButton'),
                    onPressed: checking
                        ? null
                        : () async {
                            final paths = serverType == 'fetch'
                                ? <String>[]
                                : controller.text
                                    .split('\n')
                                    .map((path) => path.trim())
                                    .where((path) => path.isNotEmpty)
                                    .toSet()
                                    .toList();
                            if ((serverType == 'filesystem' && paths.isEmpty) ||
                                paths.any((path) => !path.startsWith('/'))) {
                              setState(() => error =
                                  'Укажите хотя бы один абсолютный путь.');
                              return;
                            }
                            setState(() {
                              checking = true;
                              error = null;
                            });
                            final client = http.Client();
                            const baseUrl = String.fromEnvironment(
                                'API_BASE_URL',
                                defaultValue: 'http://localhost:3000');
                            try {
                              if (serverType == 'fetch') {
                                // Fetch server is checked through the shared MCP tools endpoint.
                                final response = await client.post(
                                  Uri.parse('$baseUrl/api/mcp/tools'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: jsonEncode(
                                      {'type': 'fetch', 'directories': []}),
                                );
                                if (response.statusCode != 200) {
                                  final payload = jsonDecode(response.body)
                                      as Map<String, dynamic>;
                                  throw Exception(payload['error'] ??
                                      'Fetch MCP недоступен');
                                }
                              } else {
                                for (final path in paths) {
                                  final uri =
                                      Uri.parse('$baseUrl/api/mcp/directories')
                                          .replace(
                                              queryParameters: {'path': path});
                                  final response = await client.get(uri);
                                  if (response.statusCode != 200) {
                                    final payload = jsonDecode(response.body)
                                        as Map<String, dynamic>;
                                    throw Exception(payload['error'] ??
                                        'Каталог недоступен: $path');
                                  }
                                }
                              }
                            } catch (cause) {
                              if (context.mounted) {
                                setState(() => error = cause
                                    .toString()
                                    .replaceFirst('Exception: ', ''));
                              }
                              return;
                            } finally {
                              client.close();
                              if (context.mounted) {
                                setState(() => checking = false);
                              }
                            }
                            if (!context.mounted) return;
                            Navigator.pop(context,
                                (type: serverType, directories: paths));
                          },
                    child: Text(checking
                        ? 'Проверка…'
                        : existingServer == null
                            ? 'Добавить'
                            : 'Сохранить'),
                  ),
                ],
              )),
    );
    controller.dispose();
    if (result == null) return;
    final server = McpServer(
        id: existingServer?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        type: result.type,
        directories: result.directories);
    if (existingServer == null) {
      repository.createMcpServer(
          type: server.type, directories: server.directories);
    } else {
      repository.updateMcpServer(server);
    }
  }

  Future<void> _delete(BuildContext context, McpServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить MCP-сервер?'),
        content: Text(
          '«${server.name}» будет удалён из общего списка и отключён у всех агентов.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) repository.deleteMcpServer(server.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final entries = repository.mcpServers;
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('addMcpServerButton'),
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('Добавить MCP'),
            ),
            body: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 96),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('MCP-серверы',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      const Text(
                          'Создайте MCP-серверы здесь, затем подключите их в карточке агента.'),
                      const SizedBox(height: 22),
                      if (entries.isEmpty)
                        const Expanded(
                            child: Center(
                                child: Text(
                                    'MCP-серверов пока нет. Создайте первый сервер.')))
                      else
                        Expanded(
                            child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final server = entries[index];
                            return AppSurface(
                                child: Column(children: [
                              ListTile(
                                leading: Icon(server.type == 'fetch'
                                    ? Icons.language
                                    : Icons.folder_outlined),
                                title: Text(server.name),
                                subtitle: Text(server.directories.join(', ')),
                                isThreeLine: true,
                              ),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      key: Key('checkMcpServer-${server.id}'),
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (_) =>
                                            McpToolsDialog(server: server),
                                      ),
                                      icon:
                                          const Icon(Icons.fact_check_outlined),
                                      label: const Text('Проверка'),
                                    ),
                                    IconButton(
                                      key: Key('editMcpServer-${server.id}'),
                                      tooltip: 'Редактировать MCP-сервер',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _add(context, server),
                                    ),
                                    IconButton(
                                      key: Key('deleteMcpServer-${server.id}'),
                                      tooltip: 'Удалить MCP-сервер',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(context, server),
                                    ),
                                  ]),
                            ]));
                          },
                        )),
                    ]),
              ),
            )),
          );
        },
      );
}
