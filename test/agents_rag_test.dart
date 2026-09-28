import 'dart:convert';

import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/agents_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('agent card selects MCP and indexed RAGs with matching buttons',
      (tester) async {
    final repository = AgentChatRepository(_Store());
    await repository.load();
    final mcp = repository
        .createMcpServer(type: 'filesystem', directories: ['/tmp/project']);
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'rags': [
            {'id': 'rag-1', 'name': 'Knowledge', 'status': 'indexed'},
            {'id': 'rag-3', 'name': 'Notes', 'status': 'indexed'},
            {'id': 'rag-2', 'name': 'Draft', 'status': 'ready'},
          ],
        }),
        200));
    await tester.pumpWidget(MaterialApp(
      home: AgentsPage(repository: repository, ragClient: client),
    ));
    await tester.tap(find.byKey(const Key('createAgentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('agentNameField')), 'Researcher');
    await tester.enterText(
        find.byKey(const Key('systemPromptField')), 'Use sources');
    await tester.ensureVisible(find.byKey(const Key('agentRagButton')));
    await tester.tap(find.byKey(const Key('agentRagButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agentRagSelection-rag-1')));
    await tester.tap(find.byKey(const Key('agentRagSelection-rag-3')));
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Knowledge, Notes'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('agentMcpButton')));
    await tester.tap(find.byKey(const Key('agentMcpButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('agentMcpSelection-${mcp.id}')));
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAgentButton')));
    await tester.pumpAndSettle();
    expect(repository.agents.single.ragIds, ['rag-1', 'rag-3']);
    expect(repository.agents.single.mcpServers.single.id, mcp.id);
    expect(find.text('RAG: 2'), findsOneWidget);
    client.close();
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
