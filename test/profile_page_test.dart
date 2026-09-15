import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits and saves all profile fields', (tester) async {
    final repository = AgentChatRepository(_MemoryStore());
    await repository.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfilePage(repository: repository)),
    ));

    await tester.enterText(find.byKey(const Key('profileNameField')), 'Анна');
    await tester.enterText(
        find.byKey(const Key('profileStyleField')), 'Кратко');
    await tester.enterText(
        find.byKey(const Key('profileFormatField')), 'Списком');
    await tester.enterText(
        find.byKey(const Key('profileConstraintsField')), 'Без эмодзи');
    await tester.ensureVisible(find.byKey(const Key('saveProfileButton')));
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pump();

    expect(repository.userProfile.name, 'Анна');
    expect(repository.userProfile.style, 'Кратко');
    expect(repository.userProfile.format, 'Списком');
    expect(repository.userProfile.constraints, 'Без эмодзи');
    expect(find.text('Профиль сохранён'), findsOneWidget);
  });
}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
