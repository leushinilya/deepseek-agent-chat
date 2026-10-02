import 'dart:convert';

import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/pages/rag_search_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final agent = AiAgent(
      id: 'agent',
      name: 'Researcher',
      systemPrompt: 'Use citations',
      model: AgentModel.deepseekPro,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026));
  final rag = <String, dynamic>{
    'id': 'rag',
    'name': 'Knowledge',
    'status': 'indexed',
    'retrievalSettings': {
      'rewriteEnabled': true,
      'filterEnabled': true,
      'candidateK': 20,
      'resultK': 5,
      'similarityThreshold': 0.3,
      'neighborRadius': 1,
      'maxExpansionCalls': 3,
      'maxSearchCalls': 3,
      'maxContextChars': 20000
    }
  };

  Widget page(http.Client client, ValueChanged<Map<String, dynamic>> onSaved) =>
      MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: RagSearchPanel(
                      rag: rag,
                      client: client,
                      baseUrl: 'http://localhost:3000',
                      agents: [agent],
                      onSaved: onSaved))));

  testWidgets('saves all retrieval settings and blocks invalid K',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    Map<String, dynamic>? saved;
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/rags/rag/retrieval');
      final settings = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(settings);
      return http.Response(
          jsonEncode({...rag, 'retrievalSettings': settings}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await tester.pumpWidget(page(client, (value) => saved = value));
    await tester.enterText(
        find.byKey(const Key('ragPrompt')), 'Цитируй документы');
    await tester.enterText(find.byKey(const Key('ragCandidateK')), '3');
    await tester.ensureVisible(find.byKey(const Key('ragSaveRetrieval')));
    await tester.tap(find.byKey(const Key('ragSaveRetrieval')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('Не больше top-K до отбора'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ragResultK')));
    await tester.enterText(find.byKey(const Key('ragResultK')), '2');
    await tester.ensureVisible(find.byKey(const Key('ragSimilarityThreshold')));
    await tester.enterText(
        find.byKey(const Key('ragSimilarityThreshold')), '0,7');
    await tester.ensureVisible(find.byKey(const Key('ragNeighborRadius')));
    await tester.enterText(find.byKey(const Key('ragNeighborRadius')), '2');
    await tester.ensureVisible(find.byKey(const Key('ragMaxExpansionCalls')));
    await tester.enterText(find.byKey(const Key('ragMaxExpansionCalls')), '1');
    expect(find.byKey(const Key('ragMaxSearchCalls')), findsNothing);
    expect(find.byKey(const Key('ragCompareSearchCalls')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('ragMaxContextChars')));
    await tester.enterText(
        find.byKey(const Key('ragMaxContextChars')), '12000');
    await tester
        .ensureVisible(find.byKey(const Key('ragCompareNeighborRadius')));
    await tester.enterText(
        find.byKey(const Key('ragCompareNeighborRadius')), 'invalid');
    await tester.ensureVisible(find.byKey(const Key('ragRewriteEnabled')));
    await tester.tap(find.byKey(const Key('ragRewriteEnabled')));
    await tester.ensureVisible(find.byKey(const Key('ragSaveRetrieval')));
    await tester.tap(find.byKey(const Key('ragSaveRetrieval')));
    await tester.pumpAndSettle();
    expect(requests.single, {
      'prompt': 'Цитируй документы',
      'rewriteEnabled': false,
      'filterEnabled': true,
      'candidateK': 3,
      'resultK': 2,
      'similarityThreshold': 0.7,
      'neighborRadius': 2,
      'maxExpansionCalls': 1,
      'maxContextChars': 12000
    });
    expect(saved!['retrievalSettings'], requests.single);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('ragCompareContextChars')))
            .controller!
            .text,
        '12000');
    client.close();
  });

  testWidgets(
      'comparison uses temporary context defaults and displays both answers',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/api/rags/rag/compare');
      expect(body, {
        'query': 'What is its price?',
        'provider': 'deepseek',
        'model': 'deepseek-v4-pro',
        'systemPrompt': 'Use citations',
        'retrievalSettings': {
          'prompt': '',
          'rewriteEnabled': true,
          'filterEnabled': true,
          'candidateK': 20,
          'resultK': 5,
          'similarityThreshold': 0.3,
          'neighborRadius': 0,
          'maxExpansionCalls': 0,
          'maxContextChars': 20000,
        }
      });
      return http.Response(
          jsonEncode({
            'baseline': {
              'answer': 'Baseline answer',
              'durationMs': 1000,
              'chunks': [],
              'rewrittenQuery': null,
              'searches': []
            },
            'improved': {
              'answer': 'Improved answer',
              'durationMs': 2000,
              'chunks': [],
              'rewrittenQuery': 'Alpha price',
              'searches': []
            },
          }),
          200);
    });
    await tester.pumpWidget(page(client, (_) {}));
    await tester.ensureVisible(find.byKey(const Key('ragComparisonQuery')));
    await tester.enterText(
        find.byKey(const Key('ragComparisonQuery')), 'What is its price?');
    await tester.ensureVisible(find.byKey(const Key('ragCompareButton')));
    expect(find.text('Сравнить'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ragCompareButton')));
    await tester.pumpAndSettle();
    expect(find.text('Baseline answer'), findsOneWidget);
    expect(find.text('Improved answer'), findsOneWidget);
    expect(find.text('Поисковый запрос: Alpha price'), findsOneWidget);
    client.close();
  });

  testWidgets('comparison sends edited context values without saving',
      (tester) async {
    Map<String, dynamic>? compared;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      compared = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'baseline': {
              'answer': 'Before',
              'durationMs': 1,
              'chunks': [],
              'searches': []
            },
            'improved': {
              'answer': 'After',
              'durationMs': 1,
              'chunks': [],
              'searches': []
            },
          }),
          200);
    });
    await tester.pumpWidget(
        page(client, (_) => fail('Comparison must not save settings')));
    for (final (key, value) in [
      (const Key('ragCompareNeighborRadius'), '2'),
      (const Key('ragCompareExpansionCalls'), '1'),
      (const Key('ragCompareContextChars'), '12000'),
    ]) {
      await tester.ensureVisible(find.byKey(key));
      await tester.enterText(find.byKey(key), value);
    }
    await tester.ensureVisible(find.byKey(const Key('ragComparisonQuery')));
    await tester.enterText(
        find.byKey(const Key('ragComparisonQuery')), 'Question');
    await tester.ensureVisible(find.byKey(const Key('ragCompareButton')));
    await tester.tap(find.byKey(const Key('ragCompareButton')));
    await tester.pumpAndSettle();
    expect(compared!['retrievalSettings'], containsPair('neighborRadius', 2));
    expect(
        compared!['retrievalSettings'], containsPair('maxExpansionCalls', 1));
    expect(compared!['retrievalSettings'], isNot(contains('maxSearchCalls')));
    expect(
        compared!['retrievalSettings'], containsPair('maxContextChars', 12000));
    client.close();
  });
}
