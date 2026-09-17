import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'memory_models.dart';
import 'memory_repository.dart';
import 'models.dart';
import 'token_counter.dart';
import 'user_profile.dart';

export 'key_value_store.dart';

class AgentHasChatsException implements Exception {
  const AgentHasChatsException(this.chatCount);
  final int chatCount;
}

class TaskHasChatsException implements Exception {
  const TaskHasChatsException(this.chatCount);
  final int chatCount;
}

class ProjectHasTasksException implements Exception {
  const ProjectHasTasksException(this.taskCount);
  final int taskCount;
}

class AgentChatRepository extends ChangeNotifier {
  AgentChatRepository(KeyValueStore store, {DateTime Function()? clock})
      : this._(store, clock ?? DateTime.now);

  AgentChatRepository._(this._store, this._clock)
      : memory = MemoryRepository(_store, clock: _clock);

  static const _storageKey = 'ai_agents_and_chats_v1';
  static const _schemaVersion = 9;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  final MemoryRepository memory;
  final _random = Random();
  final List<AiAgent> _agents = [];
  final List<AgentProject> _projects = [];
  final List<TaskStateModel> _stateModels = [];
  final List<AgentTask> _tasks = [];
  final List<AgentChat> _chats = [];
  UserProfile _userProfile = const UserProfile();
  Future<void> _pendingWrite = Future.value();

  bool isLoaded = false;
  String? loadError;
  List<AiAgent> get agents => List.unmodifiable(_agents);
  UserProfile get userProfile => _userProfile;
  List<AgentProject> get projects {
    final result = [..._projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(result);
  }

  List<TaskStateModel> get stateModels => List.unmodifiable(_stateModels);

  List<AgentTask> get tasks {
    final result = [..._tasks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(result);
  }

  Future<void> get settled async {
    await _pendingWrite;
    await memory.settled;
  }

  List<AgentChat> get chats {
    final result = [..._chats]
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return List.unmodifiable(result);
  }

  Future<void> load() async {
    try {
      final raw = await _store.read(_storageKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if ((json['version'] as int? ?? 0) > _schemaVersion) {
          throw const FormatException('Unsupported storage version');
        }
        final profile = json['userProfile'];
        if (profile is Map<String, dynamic>) {
          _userProfile = UserProfile.fromJson(profile);
        }
        _agents
          ..clear()
          ..addAll((json['agents'] as List<dynamic>? ?? const [])
              .map((item) => AiAgent.fromJson(item as Map<String, dynamic>)));
        _projects
          ..clear()
          ..addAll((json['projects'] as List<dynamic>? ?? const []).map(
              (item) => AgentProject.fromJson(item as Map<String, dynamic>)));
        _stateModels
          ..clear()
          ..addAll((json['stateModels'] as List<dynamic>? ?? const []).map(
              (item) => TaskStateModel.fromJson(item as Map<String, dynamic>)));
        _tasks
          ..clear()
          ..addAll((json['tasks'] as List<dynamic>? ?? const [])
              .map((item) => AgentTask.fromJson(item as Map<String, dynamic>)));
        _chats
          ..clear()
          ..addAll((json['chats'] as List<dynamic>? ?? const [])
              .map((item) => AgentChat.fromJson(item as Map<String, dynamic>)));
        for (var index = 0; index < _tasks.length; index++) {
          final task = _tasks[index];
          if (task.agentId != null) continue;
          final linkedChats = _chats.where((chat) => chat.taskId == task.id);
          if (linkedChats.isNotEmpty) {
            _tasks[index] = task.copyWith(agentId: linkedChats.first.agentId);
          }
        }
        for (final chat in _chats) {
          if (_tasks.any((task) => task.id == chat.taskId)) continue;
          _tasks.add(AgentTask(
            id: chat.taskId,
            projectId: chat.agentId,
            title:
                chat.title == 'Новый чат' ? 'Перенесённая задача' : chat.title,
            createdAt: chat.createdAt,
            updatedAt: chat.lastActivityAt,
          ));
        }
        for (final task in _tasks) {
          if (_projects.any((project) => project.id == task.projectId)) {
            continue;
          }
          final oldAgent = agentById(task.projectId);
          _projects.add(AgentProject(
            id: task.projectId,
            title: oldAgent == null
                ? 'Перенесённый проект'
                : 'Проект · ${oldAgent.name}',
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
          ));
        }
        await memory.load(
          chatIds: _chats.map((chat) => chat.id),
          taskIds: _tasks.map((task) => task.id),
          projectIds: _projects.map((project) => project.id),
        );
        for (var index = 0; index < _chats.length; index++) {
          final chat = _chats[index];
          if (memory.hasShortTerm(chat.id)) {
            _chats[index] = chat.copyWith(
              messages: memory.shortTermFor(chat.id).messages,
            );
          } else {
            // Migrate histories written by schema v1 into their own store.
            memory.replaceMessages(chat.id, chat.messages);
          }
        }
        await _persist();
      }
    } catch (_) {
      loadError = 'Не удалось прочитать сохранённые данные.';
    } finally {
      isLoaded = true;
      notifyListeners();
    }
  }

  AiAgent createAgent({
    required String name,
    required String systemPrompt,
    required AgentModel model,
  }) {
    final now = _clock();
    final agent = AiAgent(
      id: _id('agent'),
      name: _required(name, 'Введите имя агента.'),
      systemPrompt: _required(systemPrompt, 'Введите системный промт.'),
      model: model,
      createdAt: now,
      updatedAt: now,
    );
    _agents.add(agent);
    _changed();
    return agent;
  }

  void updateUserProfile(UserProfile profile) {
    String clean(String value, String label) {
      final result = value.trim();
      if (result.length > 4000) {
        throw ArgumentError('$label не должен превышать 4000 символов.');
      }
      return result;
    }

    final name = profile.name.trim();
    if (name.length > 100) {
      throw ArgumentError('Имя не должно превышать 100 символов.');
    }
    _userProfile = UserProfile(
      name: name,
      style: clean(profile.style, 'Стиль'),
      format: clean(profile.format, 'Формат'),
      constraints: clean(profile.constraints, 'Ограничения'),
    );
    _changed();
  }

  void updateAgent(AiAgent agent) {
    final index = _agents.indexWhere((item) => item.id == agent.id);
    if (index < 0) throw StateError('Agent not found');
    _agents[index] = agent.copyWith(
      name: _required(agent.name, 'Введите имя агента.'),
      systemPrompt: _required(agent.systemPrompt, 'Введите системный промт.'),
      updatedAt: _clock(),
    );
    _changed();
  }

  void deleteAgent(String id) {
    final linkedTasks = _tasks.where((task) => task.agentId == id).length;
    final linkedChats = _chats.where((chat) => chat.agentId == id).length;
    final linked = linkedTasks + linkedChats;
    if (linked > 0) throw AgentHasChatsException(linked);
    _agents.removeWhere((agent) => agent.id == id);
    _changed();
  }

  AgentProject createProject({required String title}) {
    final now = _clock();
    final project = AgentProject(
      id: _id('project'),
      title: _required(title, 'Введите название проекта.'),
      createdAt: now,
      updatedAt: now,
    );
    _projects.add(project);
    _changed();
    return project;
  }

  ProjectInvariant addProjectInvariant(
    String projectId, {
    required String name,
    required String description,
  }) {
    final index = _projects.indexWhere((project) => project.id == projectId);
    if (index < 0) throw StateError('Project not found');
    final invariant = ProjectInvariant(
      id: _id('invariant'),
      name: _required(name, 'Введите название инварианта.'),
      description: _required(description, 'Введите описание инварианта.'),
    );
    if (invariant.name.length > 200) {
      throw ArgumentError('Название не должно превышать 200 символов.');
    }
    if (invariant.description.length > 4000) {
      throw ArgumentError('Описание не должно превышать 4000 символов.');
    }
    _projects[index] = _projects[index].copyWith(
      invariants: [..._projects[index].invariants, invariant],
      updatedAt: _clock(),
    );
    _changed();
    return invariant;
  }

  void deleteProjectInvariant(String projectId, String invariantId) {
    final index = _projects.indexWhere((project) => project.id == projectId);
    if (index < 0) throw StateError('Project not found');
    final project = _projects[index];
    _projects[index] = project.copyWith(
      invariants: project.invariants
          .where((item) => item.id != invariantId)
          .toList(growable: false),
      updatedAt: _clock(),
    );
    _changed();
  }

  TaskStateModel createStateModel({required String title}) {
    final now = _clock();
    final model = TaskStateModel(
      id: _id('state-model'),
      title: _required(title, 'Введите название модели состояний.'),
      states: const [],
      createdAt: now,
      updatedAt: now,
    );
    _stateModels.add(model);
    _changed();
    return model;
  }

  TaskStateDefinition addStateToModel(
    String modelId, {
    required String name,
    required String description,
    required int colorValue,
  }) {
    final index = _stateModels.indexWhere((model) => model.id == modelId);
    if (index < 0) throw StateError('State model not found');
    final state = TaskStateDefinition(
      id: _id('state'),
      name: _required(name, 'Введите название состояния.'),
      description: _required(description, 'Введите описание состояния.'),
      colorValue: colorValue,
    );
    final model = _stateModels[index];
    _stateModels[index] = model.copyWith(
      states: [...model.states, state],
      updatedAt: _clock(),
    );
    _changed();
    return state;
  }

  void moveState(String modelId, String stateId, int offset) {
    final index = _stateModels.indexWhere((model) => model.id == modelId);
    if (index < 0) throw StateError('State model not found');
    final model = _stateModels[index];
    final states = [...model.states];
    final from = states.indexWhere((state) => state.id == stateId);
    final to = from + offset;
    if (from < 0 || to < 0 || to >= states.length) return;
    final state = states.removeAt(from);
    states.insert(to, state);
    _stateModels[index] = model.copyWith(states: states, updatedAt: _clock());
    _changed();
  }

  void deleteStateModel(String id) {
    if (_projects.any((project) => project.stateModelId == id)) {
      throw StateError('State model is in use');
    }
    _stateModels.removeWhere((model) => model.id == id);
    _changed();
  }

  void assignStateModelToProject(String projectId, String modelId) {
    final projectIndex =
        _projects.indexWhere((project) => project.id == projectId);
    if (projectIndex < 0) throw StateError('Project not found');
    final model = stateModelById(modelId);
    if (model == null) throw StateError('State model not found');
    final project = _projects[projectIndex];
    _projects[projectIndex] = project.copyWith(
      stateModelId: modelId,
      updatedAt: _clock(),
    );
    for (var index = 0; index < _tasks.length; index++) {
      final task = _tasks[index];
      if (task.projectId != projectId) continue;
      _tasks[index] = task.copyWith(
        currentStateId: model.states.isEmpty ? null : model.states.first.id,
        stageResults: const [],
        updatedAt: _clock(),
      );
    }
    _changed();
  }

  void updateProject(AgentProject project) {
    final index = _projects.indexWhere((item) => item.id == project.id);
    if (index < 0) throw StateError('Project not found');
    _projects[index] = project.copyWith(
      title: _required(project.title, 'Введите название проекта.'),
      updatedAt: _clock(),
    );
    _changed();
  }

  void deleteProject(String id) {
    final linked = taskCountForProject(id);
    if (linked > 0) throw ProjectHasTasksException(linked);
    _projects.removeWhere((project) => project.id == id);
    memory.clearProject(id);
    _changed();
  }

  AgentTask createTask({
    required String projectId,
    required String title,
    String? agentId,
  }) {
    if (projectById(projectId) == null) throw StateError('Project not found');
    if (agentId != null && agentById(agentId) == null) {
      throw StateError('Agent not found');
    }
    final now = _clock();
    final task = AgentTask(
      id: _id('task'),
      projectId: projectId,
      title: _required(title, 'Введите название задачи.'),
      agentId: agentId,
      createdAt: now,
      updatedAt: now,
      currentStateId: () {
        final states =
            stateModelById(projectById(projectId)?.stateModelId)?.states;
        return states == null || states.isEmpty ? null : states.first.id;
      }(),
    );
    _tasks.add(task);
    _changed();
    return task;
  }

  void updateTask(AgentTask task) {
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) throw StateError('Task not found');
    _tasks[index] = _tasks[index].copyWith(
      title: _required(task.title, 'Введите название задачи.'),
      agentId: task.agentId,
      updatedAt: _clock(),
    );
    _changed();
  }

  void completeCurrentTaskState(String taskId, String result) {
    final index = _tasks.indexWhere((item) => item.id == taskId);
    if (index < 0) throw StateError('Task not found');
    final task = _tasks[index];
    final state = currentStateForTask(task);
    final model = stateModelForTask(task);
    if (state == null || model == null) throw StateError('Task has no state');
    if (task.stageResults.any((item) => item.stateId == state.id)) {
      throw StateError('Current state result is already saved');
    }
    final stateIndex = model.states.indexWhere((item) => item.id == state.id);
    if (stateIndex < 0) throw StateError('Task state not found');
    _tasks[index] = task.copyWith(
      currentStateId: stateIndex + 1 < model.states.length
          ? model.states[stateIndex + 1].id
          : state.id,
      stageResults: [
        ...task.stageResults,
        TaskStageResult(
          stateId: state.id,
          stateName: state.name,
          result: _required(result, 'Результат этапа не должен быть пустым.'),
          completedAt: _clock(),
        ),
      ],
      updatedAt: _clock(),
    );
    _changed();
  }

  void deleteTask(String id) {
    if (taskById(id) == null) throw StateError('Task not found');
    final linkedChatIds = _chats
        .where((chat) => chat.taskId == id)
        .map((chat) => chat.id)
        .toList(growable: false);
    _chats.removeWhere((chat) => chat.taskId == id);
    for (final chatId in linkedChatIds) {
      memory.clearChat(chatId);
    }
    _tasks.removeWhere((task) => task.id == id);
    memory.clearTask(id);
    _changed();
  }

  AgentChat createChat({String? agentId, required String taskId}) {
    final task = taskById(taskId);
    if (task == null) throw StateError('Task not found');
    final selectedAgentId = task.agentId ?? agentId;
    if (selectedAgentId == null || agentById(selectedAgentId) == null) {
      throw StateError('Task agent not found');
    }
    if (task.agentId == null) {
      final taskIndex = _tasks.indexWhere((item) => item.id == taskId);
      _tasks[taskIndex] = task.copyWith(agentId: selectedAgentId);
    }
    final now = _clock();
    final chat = AgentChat(
      id: _id('chat'),
      agentId: selectedAgentId,
      taskId: task.id,
      title: 'Новый чат',
      messages: const [],
      createdAt: now,
      lastActivityAt: now,
    );
    _chats.add(chat);
    memory.replaceMessages(chat.id, const []);
    _changed();
    return chat;
  }

  ChatMessage appendMessage(
    String chatId,
    ChatRole role,
    String content, {
    int? tokenCount,
  }) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final now = _clock();
    final message = ChatMessage(
      id: _id('message'),
      role: role,
      content: _required(content, 'Сообщение не должно быть пустым.'),
      createdAt: now,
      tokenCount: tokenCount ?? estimateTokenCount(content),
    );
    final chat = _chats[index];
    var title = chat.title;
    if (role == ChatRole.user && chat.messages.isEmpty) {
      title = _makeTitle(message.content);
    }
    _chats[index] = chat.copyWith(
      title: title,
      messages: [...chat.messages, message],
      branches: chat.activeBranchId == null
          ? chat.branches
          : chat.branches
              .map((branch) => branch.id == chat.activeBranchId
                  ? branch.copyWith(messages: [...branch.messages, message])
                  : branch)
              .toList(growable: false),
      lastActivityAt: now,
    );
    memory.replaceMessages(chatId, _chats[index].messages);
    _changed();
    return message;
  }

  void deleteChat(String id) {
    _chats.removeWhere((chat) => chat.id == id);
    memory.clearChat(id);
    _changed();
  }

  ShortTermMemory shortTermMemory(String chatId) => memory.shortTermFor(chatId);

  WorkingMemory workingMemory(String taskId) => memory.workingFor(taskId);

  LongTermMemory longTermMemory(String projectId) =>
      memory.longTermFor(projectId);

  void updateWorkingMemory(String taskId, String content) {
    if (taskById(taskId) == null) throw StateError('Task not found');
    memory.saveWorking(taskId, content);
    notifyListeners();
  }

  void rememberLongTerm(String projectId, String content) {
    if (projectById(projectId) == null) throw StateError('Project not found');
    memory.rememberLongTerm(projectId, content);
    notifyListeners();
  }

  void deleteLongTermMemoryItem(String projectId, String itemId) {
    if (projectById(projectId) == null) throw StateError('Project not found');
    memory.deleteLongTermItem(projectId, itemId);
    notifyListeners();
  }

  final Set<String> _compressingChats = {};

  bool beginCompression(String chatId) => _compressingChats.add(chatId);

  void endCompression(String chatId) => _compressingChats.remove(chatId);

  void updateCompressionSettings(String chatId,
      {required bool enabled, required int max, required int min}) {
    if (min < 1 || max <= min) {
      throw ArgumentError('Укажите целые числа: 1 ≤ min < max.');
    }
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    if (_compressingChats.contains(chatId)) {
      throw StateError('Дождитесь завершения сжатия.');
    }
    _chats[index] = _chats[index].copyWith(
      contextStrategy:
          enabled ? ContextStrategy.compression : ContextStrategy.fullHistory,
      compressionMax: max,
      compressionMin: min,
    );
    _changed();
  }

  void updateContextStrategy(String chatId, ContextStrategy strategy) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    if (_compressingChats.contains(chatId)) {
      throw StateError('Дождитесь завершения обработки контекста.');
    }
    _chats[index] = _chats[index].copyWith(contextStrategy: strategy);
    _changed();
  }

  void updateWindowSize(String chatId, int size) {
    if (size < 1 || size > 200) {
      throw ArgumentError('Размер окна должен быть от 1 до 200.');
    }
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    _chats[index] = _chats[index].copyWith(windowSize: size);
    _changed();
  }

  void saveFacts(String chatId, Map<String, String> facts) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final cleaned = <String, String>{};
    for (final entry in facts.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) cleaned[key] = value;
    }
    _chats[index] = _chats[index].copyWith(facts: cleaned);
    _changed();
  }

  void createBranches(String chatId) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final chat = _chats[index];
    if (chat.branches.isNotEmpty) {
      throw StateError('Ветки уже созданы.');
    }
    final firstId = _id('branch');
    final secondId = _id('branch');
    final snapshot = List<ChatMessage>.of(chat.messages, growable: false);
    _chats[index] = chat.copyWith(
      contextStrategy: ContextStrategy.branching,
      branches: [
        ChatBranch(id: firstId, name: 'Ветка A', messages: snapshot),
        ChatBranch(id: secondId, name: 'Ветка B', messages: snapshot),
      ],
      activeBranchId: firstId,
      checkpointMessageCount: snapshot.length,
    );
    _changed();
  }

  void switchBranch(String chatId, String branchId) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final chat = _chats[index];
    ChatBranch? branch;
    for (final item in chat.branches) {
      if (item.id == branchId) {
        branch = item;
        break;
      }
    }
    if (branch == null) throw StateError('Branch not found');
    _chats[index] = chat.copyWith(
      contextStrategy: ContextStrategy.branching,
      activeBranchId: branchId,
      messages: List<ChatMessage>.of(branch.messages, growable: false),
      lastActivityAt: _clock(),
    );
    memory.replaceMessages(chatId, _chats[index].messages);
    _changed();
  }

  void saveContextSummary(String chatId, String summary, int messageCount) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final chat = _chats[index];
    if (summary.trim().isEmpty ||
        messageCount <= chat.summarizedMessageCount ||
        messageCount >= chat.messages.length) {
      throw ArgumentError('Некорректное резюме контекста.');
    }
    _chats[index] = chat.copyWith(
      contextSummary: summary.trim(),
      summarizedMessageCount: messageCount,
    );
    _changed();
  }

  AiAgent? agentById(String id) {
    for (final agent in _agents) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  AgentProject? projectById(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  TaskStateModel? stateModelById(String? id) {
    if (id == null) return null;
    for (final model in _stateModels) {
      if (model.id == id) return model;
    }
    return null;
  }

  TaskStateModel? stateModelForTask(AgentTask task) =>
      stateModelById(projectById(task.projectId)?.stateModelId);

  TaskStateDefinition? currentStateForTask(AgentTask task) {
    final model = stateModelForTask(task);
    if (model == null || task.currentStateId == null) return null;
    for (final state in model.states) {
      if (state.id == task.currentStateId) return state;
    }
    return null;
  }

  TaskStateDefinition? nextStateForTask(AgentTask task) {
    final model = stateModelForTask(task);
    final current = currentStateForTask(task);
    if (model == null || current == null) return null;
    final index = model.states.indexWhere((state) => state.id == current.id);
    return index >= 0 && index + 1 < model.states.length
        ? model.states[index + 1]
        : null;
  }

  bool isTaskComplete(AgentTask task) {
    final model = stateModelForTask(task);
    if (model == null || model.states.isEmpty) return false;
    return task.currentStateId == model.states.last.id &&
        task.stageResults
            .any((result) => result.stateId == task.currentStateId);
  }

  AgentTask? taskById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  AgentChat? chatById(String id) {
    for (final chat in _chats) {
      if (chat.id == id) return chat;
    }
    return null;
  }

  int chatCountForAgent(String id) =>
      _chats.where((chat) => chat.agentId == id).length;

  int taskCountForAgent(String id) =>
      _tasks.where((task) => task.agentId == id).length;

  int taskCountForProject(String id) =>
      _tasks.where((task) => task.projectId == id).length;

  List<AgentTask> tasksForProject(String projectId) => List.unmodifiable(
      _tasks.where((task) => task.projectId == projectId).toList());

  int chatCountForTask(String taskId) =>
      _chats.where((chat) => chat.taskId == taskId).length;

  String _id(String prefix) =>
      // Keep the bound below JavaScript's signed 32-bit shift limit. In a
      // compiled web build, `1 << 32` wraps to zero and makes nextInt throw,
      // preventing chats and messages from being created.
      '$prefix-${_clock().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}';

  String _required(String value, String message) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError(message);
    return result;
  }

  String _makeTitle(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return compact.length <= 48 ? compact : '${compact.substring(0, 48)}…';
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    final value = jsonEncode({
      'version': _schemaVersion,
      'userProfile': _userProfile.toJson(),
      'agents': _agents.map((agent) => agent.toJson()).toList(),
      'projects': _projects.map((project) => project.toJson()).toList(),
      'stateModels': _stateModels.map((model) => model.toJson()).toList(),
      'tasks': _tasks.map((task) => task.toJson()).toList(),
      'chats':
          _chats.map((chat) => chat.toJson(includeMessages: false)).toList(),
    });
    _pendingWrite =
        _pendingWrite.then((_) => _store.write(_storageKey, value)).catchError(
              (_) {},
            );
    await _pendingWrite;
  }
}
