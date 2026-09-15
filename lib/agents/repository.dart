import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'memory_models.dart';
import 'memory_repository.dart';
import 'models.dart';
import 'token_counter.dart';

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
  static const _schemaVersion = 3;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  final MemoryRepository memory;
  final _random = Random();
  final List<AiAgent> _agents = [];
  final List<AgentProject> _projects = [];
  final List<AgentTask> _tasks = [];
  final List<AgentChat> _chats = [];
  Future<void> _pendingWrite = Future.value();

  bool isLoaded = false;
  String? loadError;
  List<AiAgent> get agents => List.unmodifiable(_agents);
  List<AgentProject> get projects {
    final result = [..._projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(result);
  }

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
        _agents
          ..clear()
          ..addAll((json['agents'] as List<dynamic>? ?? const [])
              .map((item) => AiAgent.fromJson(item as Map<String, dynamic>)));
        _projects
          ..clear()
          ..addAll((json['projects'] as List<dynamic>? ?? const []).map(
              (item) => AgentProject.fromJson(item as Map<String, dynamic>)));
        _tasks
          ..clear()
          ..addAll((json['tasks'] as List<dynamic>? ?? const [])
              .map((item) => AgentTask.fromJson(item as Map<String, dynamic>)));
        _chats
          ..clear()
          ..addAll((json['chats'] as List<dynamic>? ?? const [])
              .map((item) => AgentChat.fromJson(item as Map<String, dynamic>)));
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
    final linked = _chats.where((chat) => chat.agentId == id).length;
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

  AgentTask createTask({required String projectId, required String title}) {
    if (projectById(projectId) == null) throw StateError('Project not found');
    final now = _clock();
    final task = AgentTask(
      id: _id('task'),
      projectId: projectId,
      title: _required(title, 'Введите название задачи.'),
      createdAt: now,
      updatedAt: now,
    );
    _tasks.add(task);
    _changed();
    return task;
  }

  void updateTask(AgentTask task) {
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) throw StateError('Task not found');
    _tasks[index] = task.copyWith(
      title: _required(task.title, 'Введите название задачи.'),
      updatedAt: _clock(),
    );
    _changed();
  }

  void deleteTask(String id) {
    final linked = _chats.where((chat) => chat.taskId == id).length;
    if (linked > 0) throw TaskHasChatsException(linked);
    _tasks.removeWhere((task) => task.id == id);
    memory.clearTask(id);
    _changed();
  }

  AgentChat createChat({required String agentId, required String taskId}) {
    if (agentById(agentId) == null) throw StateError('Agent not found');
    final task = taskById(taskId);
    if (task == null) throw StateError('Task not found');
    final now = _clock();
    final chat = AgentChat(
      id: _id('chat'),
      agentId: agentId,
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

  void rememberWorking(String taskId, String content) {
    if (taskById(taskId) == null) throw StateError('Task not found');
    memory.rememberWorking(taskId, content);
    notifyListeners();
  }

  void deleteWorkingMemoryItem(String taskId, String itemId) {
    if (taskById(taskId) == null) throw StateError('Task not found');
    memory.deleteWorkingItem(taskId, itemId);
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
      'agents': _agents.map((agent) => agent.toJson()).toList(),
      'projects': _projects.map((project) => project.toJson()).toList(),
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
