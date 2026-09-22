import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class McpDirectoryPicker extends StatefulWidget {
  const McpDirectoryPicker({super.key, this.client, this.baseUrl});

  final http.Client? client;
  final String? baseUrl;

  @override
  State<McpDirectoryPicker> createState() => _McpDirectoryPickerState();
}

class _McpDirectoryPickerState extends State<McpDirectoryPicker> {
  late final http.Client _client = widget.client ?? http.Client();
  String? _current;
  String? _parent;
  List<(String name, String path)> _directories = [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _open(null);
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _open(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final baseUrl = widget.baseUrl ??
          const String.fromEnvironment('API_BASE_URL',
              defaultValue: 'http://localhost:3000');
      final uri = Uri.parse('$baseUrl/api/mcp/directories')
          .replace(queryParameters: path == null ? null : {'path': path});
      final response = await _client.get(uri);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(payload['error'] ?? 'Не удалось открыть каталог.');
      }
      if (!mounted) return;
      setState(() {
        _current = payload['current'] as String?;
        _parent = payload['parent'] as String?;
        _directories = (payload['directories'] as List<dynamic>)
            .map((item) => (item['name'] as String, item['path'] as String))
            .toList();
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Выбрать каталог для MCP'),
        content: SizedBox(
          width: 560,
          height: 420,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconButton(
                key: const Key('mcpDirectoryBackButton'),
                tooltip: 'На уровень выше',
                onPressed:
                    _loading || _current == null ? null : () => _open(_parent),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                  child: SelectableText(_current ?? 'Разрешённые каталоги',
                      maxLines: 2)),
            ]),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
                child: ListView.builder(
              itemCount: _directories.length,
              itemBuilder: (context, index) {
                final directory = _directories[index];
                return ListTile(
                  key: Key('mcpDirectory-${directory.$2}'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(directory.$1),
                  onTap: _loading ? null : () => _open(directory.$2),
                );
              },
            )),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('chooseMcpDirectoryButton'),
            onPressed: _loading || _current == null
                ? null
                : () => Navigator.pop(context, _current),
            child: const Text('Выбрать эту папку'),
          ),
        ],
      );
}
