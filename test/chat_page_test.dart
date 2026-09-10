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
    provider.operation.controller.add(
      const LlmDone(promptTokens: 14, completionTokens: 9),
    );
    await provider.operation.controller.close();
    await tester.pump();

    final messages = repository.chatById(chat.id)!.messages;
    expect(messages, hasLength(2));
    expect(messages.last.content, 'Часть ответа');
    expect(messages.first.tokenCount, isNotNull);
    expect(messages.last.tokenCount, 9);
    expect(find.text('9 токенов'), findsOneWidget);
    expect(find.byKey(const Key('chatTotalTokens')), findsOneWidget);
    expect(find.byKey(const Key('chatTokenProgress')), findsOneWidget);
    expect(find.textContaining('из 262 144 токенов'), findsOneWidget);
  });

  testWidgets('compression settings validate and summary precedes answer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            repository: repository, chatId: chat.id, provider: provider)));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('compressionMaxField')))
            .enabled,
        isFalse);
    await tester.tap(find.byKey(const Key('contextCompressionSwitch')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('compressionMinField')), '1');
    await tester.enterText(find.byKey(const Key('compressionMaxField')), '1');
    await tester.pump();
    expect(find.text('Нужно: 1 ≤ min < max'), findsNWidgets(2));
    await tester.enterText(find.byKey(const Key('compressionMaxField')), '3');
    await tester.pump();
    repository.appendMessage(chat.id, ChatRole.user, 'Old question');
    repository.appendMessage(chat.id, ChatRole.assistant, 'Old answer');
    await tester.enterText(
        find.byKey(const Key('chatMessageField')), 'New question');
    await tester.tap(find.byKey(const Key('sendMessageButton')));
    await tester.pump();
    expect(provider.requests, hasLength(1));
    expect(provider.requests.first.messages, hasLength(2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Сжимаю контекст…'), findsWidgets);
    final summaryOperation = provider.operation;
    summaryOperation.controller.add(const LlmTextDelta('Remember this'));
    summaryOperation.controller.add(const LlmDone());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(provider.requests, hasLength(2));
    expect(provider.requests.last.summary, 'Remember this');
    expect(provider.requests.last.agent.systemPrompt, 'Отвечай кратко');
    expect(provider.requests.last.messages.single.content, 'New question');
    provider.operation.controller.add(const LlmTextDelta('New answer'));
    provider.operation.controller.add(const LlmDone());
    await tester.pumpAndSettle();
    expect(repository.chatById(chat.id)!.messages, hasLength(4));
    final originalQuestion = find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'Old question');
    expect(find.byKey(const Key('chatContextSummary')), findsOneWidget);
    expect(originalQuestion, findsNothing);
    final toggle = find.byKey(const Key('toggleSummarizedMessages'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(originalQuestion, findsOneWidget);
    expect(find.text('Скрыть исходные сообщения'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(originalQuestion, findsNothing);
    expect(repository.chatById(chat.id)!.messages, hasLength(4));
    unawaited(summaryOperation.controller.close());
    await provider.operation.controller.close();
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
