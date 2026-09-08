import 'dart:async';

import 'package:deepseek_agent_chat/agents/llm_provider.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AgentChatRepository repository;
  late AgentChat chat;
  late _FakeProvider provider;

  setUp(() async {
    repository = AgentChatRepository(_MemoryStore());
    await repository.load();
    final agent = repository.createAgent(
      name: 'Помощник',
      systemPrompt: 'Отвечай кратко',
      model: AgentModel.localGigaChat,
    );
    chat = repository.createChat(agent.id);
    provider = _FakeProvider();
  });

  testWidgets('sends once, renders stream and saves completed answer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));
    await tester.enterText(find.byKey(const Key('chatMessageField')), 'Привет');
    await tester.tap(find.byKey(const Key('sendMessageButton')));
    await tester.pump();

    expect(provider.requests, hasLength(1));
    expect(repository.chatById(chat.id)!.messages, hasLength(1));
    provider.operation.controller.add(const LlmTextDelta('Часть '));
    provider.operation.controller.add(const LlmTextDelta('ответа'));
    await tester.pump();
    expect(find.textContaining('Часть ответа'), findsOneWidget);
    provider.operation.controller.add(const LlmDone());
    await provider.operation.controller.close();
    await tester.pump();

    final messages = repository.chatById(chat.id)!.messages;
    expect(messages, hasLength(2));
    expect(messages.last.content, 'Часть ответа');
  });

  testWidgets('stop cancels active provider operation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));
    await tester.enterText(
        find.byKey(const Key('chatMessageField')), 'Останови');
    await tester.tap(find.byKey(const Key('sendMessageButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stopGenerationButton')));
    await tester.pump();

    expect(provider.operation.cancelled, isTrue);
    expect(find.byKey(const Key('sendMessageButton')), findsOneWidget);
  });
}

class _FakeProvider implements LlmProvider {
  final requests = <LlmRequest>[];
  late _FakeOperation operation;

  @override
  LlmOperation send(LlmRequest request) {
    requests.add(request);
    operation = _FakeOperation();
    return operation;
  }
}

class _FakeOperation implements LlmOperation {
  final controller = StreamController<LlmEvent>();
  bool cancelled = false;

  @override
  Stream<LlmEvent> get events => controller.stream;

  @override
  void cancel() {
    cancelled = true;
  }
}

class _MemoryStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
