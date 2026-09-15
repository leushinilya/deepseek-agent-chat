import 'dart:async';

import 'package:deepseek_agent_chat/agents/context_compressor.dart';
import 'package:deepseek_agent_chat/agents/llm_provider.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Store store;
  late AgentChatRepository repository;
  late AiAgent agent;
  late String id;
  late _Provider provider;

  setUp(() async {
    store = _Store();
    repository = AgentChatRepository(store);
    await repository.load();
    agent = repository.createAgent(
        name: 'Test',
        systemPrompt: 'Original',
        model: AgentModel.deepseekFlash);
    final project = repository.createProject(title: 'Test project');
    final task =
        repository.createTask(projectId: project.id, title: 'Test task');
    id = repository.createChat(agentId: agent.id, taskId: task.id).id;
    provider = _Provider();
    repository.updateCompressionSettings(id, enabled: true, max: 4, min: 2);
  });

  void append(int count) {
    for (var i = 0; i < count; i++) {
      repository.appendMessage(
          id,
          i.isEven ? ChatRole.user : ChatRole.assistant,
          'Message ${repository.chatById(id)!.messages.length}');
    }
  }

  Future<void> compress() => ContextCompressor(repository, provider)
      .compress(repository.chatById(id)!, agent);

  test('threshold, repeated summary, complete history and persistence',
      () async {
    append(3);
    await compress();
    expect(provider.requests, isEmpty);
    append(1);
    await compress();
    expect(provider.requests.single.messages.map((m) => m.content),
        ['Message 0', 'Message 1']);
    expect(repository.chatById(id)!.contextMessages.map((m) => m.content),
        ['Message 2', 'Message 3']);
    append(2);
    await compress();
    expect(provider.requests.last.summary, 'Summary');
    expect(provider.requests.last.messages.map((m) => m.content),
        ['Message 2', 'Message 3']);
    expect(repository.chatById(id)!.messages, hasLength(6));
    await repository.settled;
    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.chatById(id)!.summarizedMessageCount, 4);
    expect(restored.chatById(id)!.contextSummary, 'Summary');
    expect(restored.chatById(id)!.compressionMax, 4);
    expect(restored.chatById(id)!.compressionMin, 2);
    expect(restored.chatById(id)!.compressionEnabled, isTrue);
  });

  test('disabled compression uses full history; validates limits', () async {
    append(5);
    await compress();
    repository.updateCompressionSettings(id, enabled: false, max: 4, min: 2);
    await compress();
    expect(provider.requests, hasLength(1));
    expect(repository.chatById(id)!.contextMessages, hasLength(5));
    expect(repository.chatById(id)!.activeSummary, isEmpty);
    for (final min in [0, 4, 5]) {
      expect(
          () => repository.updateCompressionSettings(id,
              enabled: true, max: 4, min: min),
          throwsArgumentError);
    }
  });

  test('errors and incomplete or empty responses preserve context for retry',
      () async {
    append(4);
    for (final events in [
      <LlmEvent>[const LlmTextDelta('partial')],
      <LlmEvent>[const LlmDone()],
    ]) {
      provider.events = () => Stream.fromIterable(events);
      await expectLater(compress(), throwsA(isA<LlmException>()));
      expect(repository.chatById(id)!.summarizedMessageCount, 0);
    }
    provider.events = () => Stream.error(const LlmException('Failed'));
    await expectLater(compress(), throwsA(isA<LlmException>()));
    provider.events = () => Stream.fromIterable(
        [const LlmTextDelta('Retry summary'), const LlmDone()]);
    await compress();
    expect(repository.chatById(id)!.contextSummary, 'Retry summary');
    expect(repository.chatById(id)!.messages, hasLength(4));
  });

  test('cancellation and per-chat lock prevent partial or duplicate summaries',
      () async {
    append(4);
    final controller = StreamController<LlmEvent>();
    provider.events = () => controller.stream;
    final compressor = ContextCompressor(repository, provider);
    final pending = compressor.compress(repository.chatById(id)!, agent);
    await expectLater(compress(), throwsA(isA<LlmException>()));
    final expectation = expectLater(pending, throwsA(isA<LlmException>()));
    controller.add(const LlmTextDelta('partial'));
    compressor.cancel();
    await expectation;
    expect(repository.chatById(id)!.contextSummary, isEmpty);
    expect(repository.beginCompression(id), isTrue);
    repository.endCompression(id);
    await controller.close();
  });

  test('old chats load with compression disabled', () {
    final json = repository.chatById(id)!.toJson()
      ..remove('compressionEnabled')
      ..remove('compressionMax')
      ..remove('compressionMin')
      ..remove('contextSummary')
      ..remove('summarizedMessageCount')
      ..remove('contextStrategy')
      ..remove('windowSize')
      ..remove('facts')
      ..remove('branches')
      ..remove('activeBranchId')
      ..remove('checkpointMessageCount');
    final chat = AgentChat.fromJson(json);
    expect(chat.compressionEnabled, isFalse);
    expect(chat.compressionMax, 20);
    expect(chat.compressionMin, 6);
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Provider implements LlmProvider {
  final requests = <LlmRequest>[];
  Stream<LlmEvent> Function() events = () =>
      Stream.fromIterable([const LlmTextDelta('Summary'), const LlmDone()]);
  @override
  LlmOperation send(LlmRequest request) {
    requests.add(request);
    return _Operation(events());
  }
}

class _Operation implements LlmOperation {
  _Operation(this.events);
  @override
  final Stream<LlmEvent> events;
  @override
  void cancel() {}
}
