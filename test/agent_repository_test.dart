import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/agents/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStore store;
  late AgentChatRepository repository;
  var tick = 0;
  final start = DateTime.utc(2026, 1, 1);

  setUp(() async {
    store = _MemoryStore();
    repository = AgentChatRepository(
      store,
      clock: () => start.add(Duration(seconds: tick++)),
    );
    await repository.load();
  });

  test('creates and edits agents with every supported model', () {
    for (final model in AgentModel.values) {
      final agent = repository.createAgent(
        name: 'Agent ${model.id}',
        systemPrompt: 'Helpful assistant',
        model: model,
      );
      expect(agent.model.id, model.id);
      repository.updateAgent(agent.copyWith(name: 'Updated'));
      expect(repository.agentById(agent.id)!.name, 'Updated');
    }
  });

  test('creates chat, names it from first message and restores history',
      () async {
    final agent = repository.createAgent(
      name: 'Agent',
      systemPrompt: 'Prompt',
      model: AgentModel.deepseekFlash,
    );
    final project = repository.createProject(title: 'Test project');
    final task =
        repository.createTask(projectId: project.id, title: 'Test task');
    final chat = repository.createChat(agentId: agent.id, taskId: task.id);
    repository.appendMessage(
        chat.id, ChatRole.user, 'Первое сообщение пользователя');
    repository.appendMessage(
      chat.id,
      ChatRole.assistant,
      'Потоковый ответ',
      tokenCount: 17,
    );
    await repository.settled;

    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.chats.single.title, 'Первое сообщение пользователя');
    expect(restored.chats.single.messages.map((item) => item.content),
        ['Первое сообщение пользователя', 'Потоковый ответ']);
    expect(restored.chats.single.messages.last.tokenCount, 17);
  });

  test('does not delete an agent with linked chats', () {
    final agent = repository.createAgent(
      name: 'Agent',
      systemPrompt: 'Prompt',
      model: AgentModel.localGigaChat,
    );
    final project = repository.createProject(title: 'Test project');
    final task =
        repository.createTask(projectId: project.id, title: 'Test task');
    final chat = repository.createChat(agentId: agent.id, taskId: task.id);
    expect(() => repository.deleteAgent(agent.id),
        throwsA(isA<AgentHasChatsException>()));
    repository.deleteChat(chat.id);
    repository.deleteTask(task.id);
    repository.deleteAgent(agent.id);
    expect(repository.agents, isEmpty);
  });

  test('validates required agent fields and empty messages', () {
    expect(
      () => repository.createAgent(
        name: ' ',
        systemPrompt: 'Prompt',
        model: AgentModel.deepseekPro,
      ),
      throwsArgumentError,
    );
  });

  test('saves and restores user profile', () async {
    repository.updateUserProfile(const UserProfile(
      name: 'Анна',
      style: 'Кратко и дружелюбно',
      format: 'Списками',
      constraints: 'Без англицизмов',
    ));
    await repository.settled;

    final restored = AgentChatRepository(store);
    await restored.load();

    expect(restored.userProfile.name, 'Анна');
    expect(restored.userProfile.style, 'Кратко и дружелюбно');
    expect(restored.userProfile.format, 'Списками');
    expect(restored.userProfile.constraints, 'Без англицизмов');
  });
}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
