import 'dart:convert';

import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/pages/mcp_tools_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows the raw tools/list response', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/mcp/tools');
      expect(jsonDecode(request.body)['directories'], ['/projects/app']);
      return http.Response(
          jsonEncode({
            'tools': [
              {'name': 'edit_file', 'description': 'Edit a file'}
            ]
          }),
          200);
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => McpToolsDialog(
                server:
                    const McpServer(id: 'fs', directories: ['/projects/app']),
                client: client,
                baseUrl: 'http://backend')),
        child: const Text('Проверка'),
      ),
    ))));
    await tester.tap(find.text('Проверка'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"edit_file"'), findsOneWidget);
    expect(find.byKey(const Key('mcpToolsResponse')), findsOneWidget);
  });
}
