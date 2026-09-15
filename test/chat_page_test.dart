import 'dart:async';

import 'package:deepseek_agent_chat/agents/llm_provider.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AgentChatRepository repository;
  late AiAgent agent;
  late AgentProject project;
  late AgentChat chat;
  late _FakeProvider provider;

  setUp(() async {
    repository = AgentChatRepository(_MemoryStore());
    await repository.load();
    agent = repository.createAgent(
      name: 'Помощник',
      systemPrompt: 'Отвечай кратко',
      model: AgentModel.localGigaChat,
    );
    project = repository.createProject(title: 'Тестовый проект');
    final task =
        repository.createTask(projectId: project.id, title: 'Тестовая задача');
    chat = repository.createChat(agentId: agent.id, taskId: task.id);
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

  testWidgets('has no memory button and sends task working memory',
      (tester) async {
    repository.rememberWorking(chat.taskId, 'Не использовать Firebase');
    repository.rememberLongTerm(
        project.id, 'Пользователь предпочитает Flutter');
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));

    expect(find.byKey(const Key('memoryPanelButton')), findsNothing);

    await tester.enterText(
        find.byKey(const Key('chatMessageField')), 'Продолжай');
    await tester.tap(find.byKey(const Key('sendMessageButton')));
    await tester.pump();
    expect(
        provider.requests.single.workingMemory, ['Не использовать Firebase']);
    expect(provider.requests.single.longTermMemory,
        ['Пользователь предпочитает Flutter']);
  });

  testWidgets('compression settings validate and summary precedes answer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            repository: repository, chatId: chat.id, provider: provider)));
    expect(find.byKey(const Key('compressionMaxField')), findsNothing);
    await tester.tap(find.byKey(const Key('contextStrategyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compression').last);
    await tester.pumpAndSettle();
    expect(repository.chatById(chat.id)!.contextStrategy,
        ContextStrategy.compression);
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

  testWidgets('switches context strategies and creates two branches',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));

    await tester.tap(find.byKey(const Key('contextStrategyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sliding Window').last);
    await tester.pumpAndSettle();
    expect(repository.chatById(chat.id)!.contextStrategy,
        ContextStrategy.slidingWindow);
    expect(find.byKey(const Key('contextWindowSizeField')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('contextWindowSizeField')), '4');
    expect(repository.chatById(chat.id)!.windowSize, 4);

    await tester.tap(find.byKey(const Key('contextStrategyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Branching').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('createBranchesButton')));
    await tester.pumpAndSettle();
    final branched = repository.chatById(chat.id)!;
    expect(branched.branches, hasLength(2));
    expect(find.byKey(const Key('activeBranchDropdown')), findsOneWidget);
  });

  testWidgets('sliding window collapses and expands unused history',
      (tester) async {
    for (var i = 0; i < 5; i++) {
      repository.appendMessage(
        chat.id,
        i.isEven ? ChatRole.user : ChatRole.assistant,
        'Window message $i',
      );
    }
    repository.updateWindowSize(chat.id, 2);
    repository.updateContextStrategy(chat.id, ContextStrategy.slidingWindow);
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));

    expect(find.byKey(const Key('chatSlidingWindowSummary')), findsOneWidget);
    final firstBubble = find.byWidgetPredicate((widget) =>
        widget is SelectableText && widget.data == 'Window message 0');
    expect(firstBubble, findsNothing);
    expect(find.text('Window message 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggleSlidingWindowMessages')));
    await tester.pumpAndSettle();
    expect(firstBubble, findsOneWidget);
    expect(find.text('Не входит в Sliding Window'), findsNWidgets(3));
    expect(find.text('Конец неиспользуемой истории'), findsOneWidget);
  });

  testWidgets('sticky facts renders a separate card on the right',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repository.saveFacts(chat.id, {
      'goal': 'Релиз в пятницу',
      'tone': 'Кратко',
    });
    repository.updateContextStrategy(chat.id, ContextStrategy.stickyFacts);
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));

    final facts = find.byKey(const Key('chatFactsBlock'));
    final composer = find.byKey(const Key('chatMessageField'));
    expect(facts, findsOneWidget);
    expect(find.text('Релиз в пятницу'), findsOneWidget);
    expect(tester.getTopLeft(facts).dx,
        greaterThan(tester.getTopLeft(composer).dx));
  });

  testWidgets('selecting sticky facts backfills an existing conversation',
      (tester) async {
    repository.appendMessage(chat.id, ChatRole.user, 'Меня зовут Алексей');
    repository.appendMessage(
        chat.id, ChatRole.assistant, 'Приятно познакомиться');
    await tester.pumpWidget(MaterialApp(
      home:
          ChatPage(repository: repository, chatId: chat.id, provider: provider),
    ));

    await tester.tap(find.byKey(const Key('contextStrategyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sticky Facts').last);
    await tester.pump();
    expect(provider.requests, hasLength(1));
    expect(find.text('Обновляю facts…'), findsOneWidget);
    provider.operation.controller.add(const LlmTextDelta('{"name":"Алексей"}'));
    provider.operation.controller.add(const LlmDone());
    await tester.pumpAndSettle();

    expect(repository.chatById(chat.id)!.facts, {'name': 'Алексей'});
    expect(find.text('Алексей'), findsOneWidget);
    expect(find.byKey(const Key('refreshFactsButton')), findsOneWidget);
    unawaited(provider.operation.controller.close());
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
