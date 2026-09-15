import 'dart:async';

import 'package:deepseek_agent_chat/agents/facts_updater.dart';
import 'package:deepseek_agent_chat/agents/llm_provider.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Store store;
  late AgentChatRepository repository;
  late AiAgent agent;
  late String chatId;

  setUp(() async {
    store = _Store();
    repository = AgentChatRepository(store);
    await repository.load();
    agent = repository.createAgent(
      name: 'Test',
      systemPrompt: 'System',
      model: AgentModel.deepseekFlash,
    );
    final project = repository.createProject(title: 'Test project');
    final task =
        repository.createTask(projectId: project.id, title: 'Test task');
    chatId = repository.createChat(agentId: agent.id, taskId: task.id).id;
  });

  test('sliding window keeps full history but sends only last N messages', () {
    for (var i = 0; i < 6; i++) {
      repository.appendMessage(
        chatId,
        i.isEven ? ChatRole.user : ChatRole.assistant,
        'Message $i',
      );
    }
    repository.updateWindowSize(chatId, 3);
    repository.updateContextStrategy(chatId, ContextStrategy.slidingWindow);

    final chat = repository.chatById(chatId)!;
    expect(chat.messages, hasLength(6));
    expect(chat.contextMessages.map((message) => message.content),
        ['Message 3', 'Message 4', 'Message 5']);
  });

  test('sticky facts are updated from every user message and persist',
      () async {
    repository.updateContextStrategy(chatId, ContextStrategy.stickyFacts);
    repository.appendMessage(chatId, ChatRole.user, 'Цель — релиз в пятницу');
    final provider =
        _Provider('''{"goal":"Релиз в пятницу","tone":"Кратко"}''');

    await FactsUpdater(repository, provider)
        .update(repository.chatById(chatId)!, agent);

    expect(repository.chatById(chatId)!.facts,
        {'goal': 'Релиз в пятницу', 'tone': 'Кратко'});
    expect(provider.requests.single.messages.single.content,
        'Цель — релиз в пятницу');
    await repository.settled;
    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.chatById(chatId)!.facts['goal'], 'Релиз в пятницу');
    expect(restored.chatById(chatId)!.contextStrategy,
        ContextStrategy.stickyFacts);
  });

  test('sticky facts accepts local model name/value stream and merges it',
      () async {
    repository.updateContextStrategy(chatId, ContextStrategy.stickyFacts);
    repository.saveFacts(chatId, {'tone': 'Кратко'});
    repository.appendMessage(
        chatId, ChatRole.user, 'Меня зовут Алексей, релиз к пятнице');
    final provider = _Provider(
        '''{"name":"user_name","value":"Алексей"}, {"name":"deadline","value":"пятница"}''');

    await FactsUpdater(repository, provider)
        .update(repository.chatById(chatId)!, agent);

    expect(repository.chatById(chatId)!.facts, {
      'tone': 'Кратко',
      'user_name': 'Алексей',
      'deadline': 'пятница',
    });
  });

  test('sticky facts normalizes DeepSeek reasoning, wrapper and typed values',
      () async {
    repository.updateContextStrategy(chatId, ContextStrategy.stickyFacts);
    repository.appendMessage(
        chatId, ChatRole.user, 'Нужен быстрый и надёжный релиз');
    final provider = _Provider('''
<think>Размышление модели</think>
Обновлённые факты:
```json
{"facts":{"goal":"release","constraints":["fast","safe"],"priority":1}}
```
''');

    await FactsUpdater(repository, provider)
        .update(repository.chatById(chatId)!, agent);

    expect(repository.chatById(chatId)!.facts, {
      'goal': 'release',
      'constraints': 'fast, safe',
      'priority': '1',
    });
  });

  test('two branches continue independently from one checkpoint', () async {
    repository.appendMessage(chatId, ChatRole.user, 'Общий вопрос');
    repository.appendMessage(chatId, ChatRole.assistant, 'Общий ответ');
    repository.createBranches(chatId);
    var chat = repository.chatById(chatId)!;
    final branchA = chat.branches[0].id;
    final branchB = chat.branches[1].id;
    expect(chat.checkpointMessageCount, 2);

    repository.appendMessage(chatId, ChatRole.user, 'Путь A');
    repository.switchBranch(chatId, branchB);
    expect(repository.chatById(chatId)!.messages, hasLength(2));
    repository.appendMessage(chatId, ChatRole.user, 'Путь B');
    repository.switchBranch(chatId, branchA);
    chat = repository.chatById(chatId)!;
    expect(chat.messages.last.content, 'Путь A');
    expect(
        chat.messages.any((message) => message.content == 'Путь B'), isFalse);

    await repository.settled;
    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.chatById(chatId)!.branches, hasLength(2));
    expect(restored.chatById(chatId)!.activeBranchId, branchA);
  });
}

class _Provider implements LlmProvider {
  _Provider(this.response);
  final String response;
  final requests = <LlmRequest>[];

  @override
  LlmOperation send(LlmRequest request) {
    requests.add(request);
    return _Operation(Stream.fromIterable([
      LlmTextDelta(response),
      const LlmDone(),
    ]));
  }
}

class _Operation implements LlmOperation {
  _Operation(this.events);
  @override
  final Stream<LlmEvent> events;
  @override
  void cancel() {}
}

class _Store implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
