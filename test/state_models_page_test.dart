import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/state_models_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates a state model and configured state', (tester) async {
    final repository = AgentChatRepository(_Store());
    await repository.load();
    await tester
        .pumpWidget(MaterialApp(home: StateModelsPage(repository: repository)));

    await tester.tap(find.byKey(const Key('createStateModelButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('stateModelTitleField')), 'Разработка');
    await tester.tap(find.byKey(const Key('saveStateModelButton')));
    await tester.pumpAndSettle();

    final model = repository.stateModels.single;
    await tester.tap(find.byKey(Key('addState-${model.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('stateNameField')), 'Планирование');
    await tester.enterText(find.byKey(const Key('stateDescriptionField')),
        'Составить план реализации');
    await tester.tap(find.byKey(const Key('stateColor-4286535385')));
    await tester.tap(find.byKey(const Key('saveStateButton')));
    await tester.pumpAndSettle();

    final state = repository.stateModels.single.states.single;
    expect(state.name, 'Планирование');
    expect(state.description, 'Составить план реализации');
    expect(state.colorValue, 0xFF7F56D9);
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
