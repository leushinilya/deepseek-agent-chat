import 'dart:convert';

import 'package:deepseek_agent_chat/pages/rag_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('RAG card renames and displays the saved index', (tester) async {
    var name = 'Knowledge';
    var deleted = false;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/rags' && request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'rags': deleted
                  ? []
                  : [
                      {
                        'id': 'rag-1',
                        'name': name,
                        'status': 'indexed',
                        'documentCount': 1,
                        'chunkCount': 1
                      }
                    ],
            }),
            200);
      }
      if (path == '/api/rags/rag-1' && request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'id': 'rag-1',
              'name': name,
              'status': 'indexed',
              'strategy': 'structure',
              'chunkCount': 1,
              'documents': [
                {'id': 'doc-1', 'name': 'guide.md'}
              ],
            }),
            200);
      }
      if (path == '/api/rags/rag-1' && request.method == 'PATCH') {
        name = (jsonDecode(request.body) as Map<String, dynamic>)['name']
            as String;
        return http.Response(
            jsonEncode({
              'id': 'rag-1',
              'name': name,
              'status': 'indexed',
              'strategy': 'structure',
              'chunkCount': 1,
              'documents': [
                {'id': 'doc-1', 'name': 'guide.md'}
              ],
            }),
            200);
      }
      if (path == '/api/rags/rag-1' && request.method == 'DELETE') {
        deleted = true;
        return http.Response('{"deleted":true}', 200);
      }
      if (path == '/api/rags/rag-1/chunks') {
        return http.Response(
            jsonEncode({
              'total': 1,
              'offset': 0,
              'limit': 10,
              'chunks': [
                {
                  'chunkId': 'doc-1:1',
                  'source': 'guide.md',
                  'title': 'guide.md',
                  'section': 'Intro',
                  'content': 'Useful fact',
                  'embedding': [0.1, 0.2],
                }
              ],
            }),
            200);
      }
      return http.Response('{}', 404);
    });
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: RagPage(client: client))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ragDetailsDialog')), findsNothing);
    expect(find.byKey(const Key('ragRenameButton')), findsNothing);
    await tester.tap(find.byKey(const Key('rag-rag-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ragDetailsDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ragRenameButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ragRenameField')), 'Updated');
    await tester.tap(find.byKey(const Key('ragRenameSaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('Updated'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('ragCheckButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ragCheckButton')));
    await tester.pumpAndSettle();
    expect(find.text('Локальный индекс: Updated'), findsOneWidget);
    expect(find.text('Чанки 1–1 из 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ragChunk-doc-1:1')));
    await tester.pumpAndSettle();
    expect(find.text('source: guide.md'), findsOneWidget);
    expect(find.text('title/file: guide.md'), findsOneWidget);
    expect(find.text('section: Intro'), findsOneWidget);
    expect(find.text('chunk_id: doc-1:1'), findsWidgets);
    expect(find.text('Useful fact'), findsOneWidget);
    expect(find.text('[0.1,0.2]'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('ragEmbedding-doc-1:1')));
    await tester.tap(find.byKey(const Key('ragEmbedding-doc-1:1')));
    await tester.pumpAndSettle();
    expect(find.text('Эмбеддинг чанка'), findsOneWidget);
    expect(find.text('Размерность: 2'), findsOneWidget);
    expect(find.text('[0.1,0.2]'), findsOneWidget);
    await tester.tap(find.text('Закрыть').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрыть').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрыть').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ragDetailsDialog')), findsNothing);
    expect(find.byKey(const Key('ragRenameButton')), findsNothing);
    await tester.tap(find.byKey(const Key('rag-rag-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ragDeleteButton')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить RAG?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ragConfirmDeleteButton')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.byKey(const Key('rag-rag-1')), findsNothing);
    expect(find.byKey(const Key('ragDetailsDialog')), findsNothing);
    client.close();
  });

  testWidgets('RAG list shows separate cards and deletes from a card',
      (tester) async {
    var deleted = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/rags' && request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'rags': [
                if (!deleted)
                  {
                    'id': 'rag-1',
                    'name': 'First',
                    'status': 'indexed',
                    'documentCount': 1,
                    'chunkCount': 2,
                  },
                {
                  'id': 'rag-2',
                  'name': 'Second',
                  'status': 'ready',
                  'documentCount': 3,
                  'chunkCount': 0,
                },
              ],
            }),
            200);
      }
      if (request.url.path == '/api/rags/rag-1' && request.method == 'DELETE') {
        deleted = true;
        return http.Response('{"deleted":true}', 200);
      }
      return http.Response('{}', 404);
    });
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: RagPage(client: client))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rag-rag-1')), findsOneWidget);
    expect(find.byKey(const Key('rag-rag-2')), findsOneWidget);
    expect(find.byKey(const Key('ragDetailsDialog')), findsNothing);
    await tester.tap(find.byKey(const Key('ragDelete-rag-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ragDetailsDialog')), findsNothing);
    await tester.tap(find.byKey(const Key('ragConfirmDeleteButton')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.byKey(const Key('rag-rag-1')), findsNothing);
    expect(find.byKey(const Key('rag-rag-2')), findsOneWidget);
    client.close();
  });
}
