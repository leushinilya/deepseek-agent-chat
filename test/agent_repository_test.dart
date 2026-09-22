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

  test('MCP servers belong to an agent and survive reload', () async {
    final agent = repository.createAgent(
        name: 'Editor',
        systemPrompt: 'Edit files',
        model: AgentModel.deepseekFlash);
    repository.updateAgent(agent.copyWith(mcpServers: const [
      McpServer(id: 'filesystem-1', directories: ['/tmp/project']),
    ]));
    await repository.settled;
    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.agentById(agent.id)!.mcpServers.single.directories,
        ['/tmp/project']);
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

  test('configured task states advance strictly and persist results', () async {
    final project = repository.createProject(title: 'State project');
    final model = repository.createStateModel(title: 'Delivery');
    final planning = repository.addStateToModel(model.id,
        name: 'Planning', description: 'Create a plan', colorValue: 0xFF0000FF);
    final execution = repository.addStateToModel(model.id,
        name: 'Execution', description: 'Implement', colorValue: 0xFF00FF00);
    final validation = repository.addStateToModel(model.id,
        name: 'Validation', description: 'Validate', colorValue: 0xFFFF0000);
    repository.assignStateModelToProject(project.id, model.id);
    final task = repository.createTask(
      projectId: project.id,
      title: 'State task',
    );

    expect(task.currentStateId, planning.id);
    repository.updateTask(task.copyWith(currentStateId: validation.id));
    expect(repository.taskById(task.id)!.currentStateId, planning.id);
    repository.completeCurrentTaskState(task.id, 'Implementation plan');
    expect(repository.taskById(task.id)!.currentStateId, execution.id);
    expect(repository.taskById(task.id)!.stageResults.single.result,
        'Implementation plan');
    repository.completeCurrentTaskState(task.id, 'Implemented feature');
    expect(repository.taskById(task.id)!.currentStateId, validation.id);
    repository.completeCurrentTaskState(task.id, 'Validation passed');
    expect(repository.isTaskComplete(repository.taskById(task.id)!), isTrue);
    expect(
      () => repository.completeCurrentTaskState(task.id, 'Cannot advance'),
      throwsA(isA<StateError>()),
    );
    await repository.settled;

    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.taskById(task.id)!.currentStateId, validation.id);
    expect(restored.taskById(task.id)!.stageResults, hasLength(3));
    expect(restored.stateModels.single.states, hasLength(3));
  });

  test('legacy task without a configured model has no state', () {
    final task = AgentTask.fromJson({
      'id': 'legacy-task',
      'projectId': 'project',
      'title': 'Legacy',
      'createdAt': start.toIso8601String(),
      'updatedAt': start.toIso8601String(),
    });

    expect(task.currentStateId, isNull);
  });

  test('project invariants are validated, persisted and deleted', () async {
    final project = repository.createProject(title: 'Safe project');
    final invariant = repository.addProjectInvariant(
      project.id,
      name: 'Не удалять данные',
      description: 'Агент не должен удалять пользовательские данные.',
    );
    expect(repository.projectById(project.id)!.invariants.single.name,
        'Не удалять данные');
    expect(
      () => repository.addProjectInvariant(project.id,
          name: ' ', description: 'Описание'),
      throwsArgumentError,
    );
    await repository.settled;

    final restored = AgentChatRepository(store);
    await restored.load();
    expect(restored.projectById(project.id)!.invariants.single.description,
        'Агент не должен удалять пользовательские данные.');

    restored.deleteProjectInvariant(project.id, invariant.id);
    expect(restored.projectById(project.id)!.invariants, isEmpty);
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

  test('deleting a task also deletes all linked chats', () {
    final agent = repository.createAgent(
      name: 'Agent',
      systemPrompt: 'Prompt',
      model: AgentModel.localGigaChat,
    );
    final project = repository.createProject(title: 'Project');
    final task = repository.createTask(projectId: project.id, title: 'Task');
    repository.createChat(agentId: agent.id, taskId: task.id);
    repository.createChat(agentId: agent.id, taskId: task.id);

    repository.deleteTask(task.id);

    expect(repository.taskById(task.id), isNull);
    expect(repository.chats, isEmpty);
  });

  test('task agent is used when creating its chats', () {
    final first = repository.createAgent(
      name: 'First',
      systemPrompt: 'First prompt',
      model: AgentModel.localGigaChat,
    );
    final second = repository.createAgent(
      name: 'Second',
      systemPrompt: 'Second prompt',
      model: AgentModel.deepseekFlash,
    );
    final project = repository.createProject(title: 'Project');
    final task = repository.createTask(
      projectId: project.id,
      agentId: first.id,
      title: 'Task',
    );

    final firstChat = repository.createChat(taskId: task.id);
    expect(firstChat.agentId, first.id);

    repository.updateTask(task.copyWith(agentId: second.id));
    final secondChat = repository.createChat(taskId: task.id);
    expect(secondChat.agentId, second.id);
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
