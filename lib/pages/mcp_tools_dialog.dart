import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../agents/models.dart';

class McpToolsDialog extends StatefulWidget {
  const McpToolsDialog(
      {required this.server, this.client, this.baseUrl, super.key});

  final McpServer server;
  final http.Client? client;
  final String? baseUrl;

  @override
  State<McpToolsDialog> createState() => _McpToolsDialogState();
}

class _McpToolsDialogState extends State<McpToolsDialog> {
  late final http.Client _client = widget.client ?? http.Client();
  String? _response;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _response = null;
    });
    try {
      final baseUrl = widget.baseUrl ??
          const String.fromEnvironment('API_BASE_URL',
              defaultValue: 'http://localhost:3000');
      final response = await _client.post(
        Uri.parse('$baseUrl/api/mcp/tools'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(widget.server.toJson()),
      );
      final payload = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(payload is Map ? payload['error'] : 'Ошибка MCP');
      }
      if (mounted) {
        setState(() =>
            _response = const JsonEncoder.withIndent('  ').convert(payload));
      }
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
        title: const Text('Ответ MCP: tools/list'),
        content: SizedBox(
          width: 680,
          height: 440,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? SelectableText(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                  : SingleChildScrollView(
                      child: SelectableText(_response ?? '{}',
                          key: const Key('mcpToolsResponse'))),
        ),
        actions: [
          TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('Повторить')),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть')),
        ],
      );
}
