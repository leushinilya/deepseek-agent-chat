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

  Future<void> _add(BuildContext context,
      [AiAgent? existingAgent, McpServer? existingServer]) async {
    if (repository.agents.isEmpty) return;
    final controller =
        TextEditingController(text: existingServer?.directories.join('\n'));
    var agentId = existingAgent?.id ?? repository.agents.first.id;
    String? error;
    var checking = false;
    final result =
        await showDialog<({String agentId, List<String> directories})>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: Text(existingServer == null
                    ? 'Добавить Filesystem MCP'
                    : 'Редактировать Filesystem MCP'),
                content: SizedBox(
                  width: 520,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                      initialValue: agentId,
                      decoration: const InputDecoration(labelText: 'Агент'),
                      items: [
                        for (final agent in repository.agents)
                          DropdownMenuItem(
                              value: agent.id, child: Text(agent.name))
                      ],
                      onChanged: existingServer == null
                          ? (value) {
                              if (value != null) {
                                setState(() => agentId = value);
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
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
                                  'Разрешённые каталоги на машине backend',
                              hintText: '/absolute/path/to/project',
                              helperText:
                                  'Один путь в строке; внутри MCP_ALLOWED_ROOTS',
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
                              controller.text =
                                  existing.isEmpty ? path : '$existing\n$path';
                              setState(() => error = null);
                            },
                          ),
                        ]),
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
                            final paths = controller.text
                                .split('\n')
                                .map((path) => path.trim())
                                .where((path) => path.isNotEmpty)
                                .toSet()
                                .toList();
                            if (paths.isEmpty ||
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
                            try {
                              const baseUrl = String.fromEnvironment(
                                  'API_BASE_URL',
                                  defaultValue: 'http://localhost:3000');
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
                                (agentId: agentId, directories: paths));
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
    final agent = repository.agentById(result.agentId);
    if (agent == null) return;
    final server = McpServer(
        id: existingServer?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        directories: result.directories);
    repository.updateAgent(agent.copyWith(mcpServers: [
      ...agent.mcpServers.where((item) => item.id != server.id),
      server,
    ]));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final entries = [
            for (final agent in repository.agents)
              for (final server in agent.mcpServers)
                (agent: agent, server: server)
          ];
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('addMcpServerButton'),
              onPressed: repository.agents.isEmpty ? null : () => _add(context),
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
                          'Инструменты назначаются конкретному ИИ-агенту.'),
                      const SizedBox(height: 22),
                      if (entries.isEmpty)
                        const Expanded(
                            child: Center(
                                child: Text(
                                    'MCP-серверов пока нет. Создайте агента и добавьте сервер.')))
                      else
                        Expanded(
                            child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return AppSurface(
                                child: Column(children: [
                              ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(entry.server.name),
                                subtitle: Text(
                                    '${entry.agent.name}\n${entry.server.directories.join(', ')}'),
                                isThreeLine: true,
                              ),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      key: Key(
                                          'checkMcpServer-${entry.server.id}'),
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (_) => McpToolsDialog(
                                            server: entry.server),
                                      ),
                                      icon:
                                          const Icon(Icons.fact_check_outlined),
                                      label: const Text('Проверка'),
                                    ),
                                    IconButton(
                                      key: Key(
                                          'editMcpServer-${entry.server.id}'),
                                      tooltip: 'Редактировать MCP-сервер',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _add(
                                          context, entry.agent, entry.server),
                                    ),
                                    IconButton(
                                      key: Key(
                                          'deleteMcpServer-${entry.server.id}'),
                                      tooltip: 'Удалить MCP-сервер',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => repository
                                          .updateAgent(entry.agent.copyWith(
                                        mcpServers: entry.agent.mcpServers
                                            .where((server) =>
                                                server.id != entry.server.id)
                                            .toList(),
                                      )),
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
