import 'dart:convert';

import 'package:deepseek_agent_chat/agents/memory_repository.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Store store;
  late AgentChatRepository repository;
  late AiAgent agent;
  late AgentProject project;
  late AgentTask task;
  late AgentChat firstChat;

  setUp(() async {
    store = _Store();
    repository = AgentChatRepository(store);
    await repository.load();
    agent = repository.createAgent(
      name: 'Memory agent',
      systemPrompt: 'Use memory',
      model: AgentModel.deepseekFlash,
    );
    project = repository.createProject(title: 'Memory project');
    task = repository.createTask(
      projectId: project.id,
      agentId: agent.id,
      title: 'Memory task',
    );
    firstChat = repository.createChat(taskId: task.id);
  });

  test('stores dialogue, working and long-term memory under separate keys',
      () async {
    repository.appendMessage(firstChat.id, ChatRole.user, 'Current message');
    repository.updateWorkingMemory(task.id, 'Current goal');
    repository.rememberLongTerm(project.id, 'Prefers Flutter');
    await repository.settled;

    final shortKey = '${MemoryRepository.shortTermPrefix}${firstChat.id}';
    final workingKey = '${MemoryRepository.workingPrefix}${task.id}';
    final longKey = '${MemoryRepository.longTermPrefix}${project.id}';
    expect(store.values.keys, containsAll([shortKey, workingKey, longKey]));
    final metadata = jsonDecode(store.values['ai_agents_and_chats_v1']!);
    expect(metadata['chats'].single.containsKey('messages'), isFalse,
        reason: 'История должна храниться отдельно от метаданных чата.');
    expect(jsonDecode(store.values[shortKey]!)['messages'].single['content'],
        'Current message');
    expect(jsonDecode(store.values[workingKey]!)['content'], 'Current goal');
    expect(jsonDecode(store.values[longKey]!)['content'], 'Prefers Flutter');
  });

  test('task memory is shared by its chats and project memory also applies',
      () async {
    final secondChat =
        repository.createChat(agentId: agent.id, taskId: task.id);
    repository.updateWorkingMemory(task.id, 'Shared task memory');
    repository.rememberLongTerm(project.id, 'Shared profile');

    expect(repository.workingMemory(secondChat.taskId).content,
        'Shared task memory');
    expect(repository.longTermMemory(project.id).content, 'Shared profile');
  });

  test('different tasks have isolated working memory', () {
    final otherTask =
        repository.createTask(projectId: project.id, title: 'Other task');
    repository.updateWorkingMemory(task.id, 'Only first task');
    expect(repository.workingMemory(otherTask.id).content, isEmpty);
  });

  test('task requires project and valid agent; chat requires task', () {
    expect(() => repository.createTask(projectId: 'missing', title: 'Invalid'),
        throwsStateError);
    expect(
      () => repository.createTask(
        projectId: project.id,
        agentId: 'missing',
        title: 'Invalid',
      ),
      throwsStateError,
    );
    expect(() => repository.createChat(agentId: agent.id, taskId: 'missing'),
        throwsStateError);
  });

  test('restores each memory type independently', () async {
    repository.appendMessage(firstChat.id, ChatRole.user, 'Saved dialogue');
    repository.updateWorkingMemory(task.id, 'Saved task');
    repository.rememberLongTerm(project.id, 'Saved knowledge');
    await repository.settled;

    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.chatById(firstChat.id)!.messages.single.content,
        'Saved dialogue');
    expect(restored.workingMemory(task.id).content, 'Saved task');
    expect(restored.longTermMemory(project.id).content, 'Saved knowledge');
  });

  test('migrates legacy chats into required tasks with their working memory',
      () async {
    await repository.settled;
    final metadata = jsonDecode(store.values['ai_agents_and_chats_v1']!)
        as Map<String, dynamic>;
    metadata.remove('tasks');
    metadata.remove('projects');
    final legacyChat =
        (metadata['chats'] as List<dynamic>).single as Map<String, dynamic>;
    legacyChat.remove('taskId');
    metadata['version'] = 1;
    store.values['ai_agents_and_chats_v1'] = jsonEncode(metadata);
    store.values['${MemoryRepository.workingPrefix}${firstChat.id}'] =
        jsonEncode({
      'chatId': firstChat.id,
      'items': [
        {
          'id': 'legacy-memory',
          'content': 'Legacy task context',
          'createdAt': DateTime.utc(2026).toIso8601String(),
        }
      ],
    });

    final restored = AgentChatRepository(store);
    await restored.load();
    final migratedChat = restored.chatById(firstChat.id)!;
    expect(restored.taskById(migratedChat.taskId), isNotNull);
    expect(restored.workingMemory(migratedChat.taskId).content,
        'Legacy task context');
  });

  test('migrates long-term items into one prompt and persists replacement',
      () async {
    await repository.settled;
    final key = '${MemoryRepository.longTermPrefix}${project.id}';
    store.values[key] = jsonEncode({
      'projectId': project.id,
      'items': [
        {'content': 'First preference'},
        {'content': 'Second decision'},
      ],
    });
    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.longTermMemory(project.id).content,
        'First preference\n\nSecond decision');
    restored.updateLongTermMemory(project.id, 'Replacement prompt');
    await restored.settled;
    final reloaded = AgentChatRepository(store);
    await reloaded.load();
    expect(reloaded.longTermMemory(project.id).content, 'Replacement prompt');
    expect(jsonDecode(store.values[key]!).containsKey('items'), isFalse);
    restored.updateLongTermMemory(project.id, '');
    await restored.settled;
    final cleared = AgentChatRepository(store);
    await cleared.load();
    expect(cleared.longTermMemory(project.id).promptMessages, isEmpty);
  });

  test('ordinary messages do not implicitly enter durable memories', () {
    repository.appendMessage(firstChat.id, ChatRole.user, 'Do not classify me');
    expect(repository.workingMemory(task.id).content, isEmpty);
    expect(repository.longTermMemory(project.id).content, isEmpty);
  });

  test('clears unified working and long-term memory', () {
    repository.updateWorkingMemory(task.id, 'Temporary task');
    repository.rememberLongTerm(project.id, 'Outdated preference');

    repository.updateWorkingMemory(task.id, '');
    repository.updateLongTermMemory(project.id, '');

    expect(repository.workingMemory(task.id).content, isEmpty);
    expect(repository.longTermMemory(project.id).content, isEmpty);
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
