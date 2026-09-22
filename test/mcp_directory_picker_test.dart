import 'dart:convert';

import 'package:deepseek_agent_chat/pages/mcp_directory_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('selects a backend directory from the browser', (tester) async {
    String? selected;
    final client = MockClient((request) async {
      final path = request.url.queryParameters['path'];
      final body = path == null
          ? {
              'current': null,
              'parent': null,
              'directories': [
                {'name': '/projects', 'path': '/projects'}
              ]
            }
          : {
              'current': '/projects',
              'parent': null,
              'directories': [
                {'name': 'app', 'path': '/projects/app'}
              ]
            };
      return http.Response(jsonEncode(body), 200);
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          selected = await showDialog<String>(
              context: context,
              builder: (_) => McpDirectoryPicker(
                  client: client, baseUrl: 'http://backend'));
        },
        child: const Text('Открыть'),
      ),
    ))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('/projects'), findsOneWidget);
    await tester.tap(find.text('/projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseMcpDirectoryButton')));
    await tester.pumpAndSettle();
    expect(selected, '/projects');
  });
}
