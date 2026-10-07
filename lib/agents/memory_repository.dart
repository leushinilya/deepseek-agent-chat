import 'dart:convert';

import 'key_value_store.dart';
import 'memory_models.dart';
import 'models.dart';

class MemoryRepository {
  MemoryRepository(this._store);

  static const shortTermPrefix = 'memory_short_term_v1_';
  static const workingPrefix = 'memory_working_v1_';
  static const longTermPrefix = 'memory_long_term_v1_';

  final KeyValueStore _store;
  final Map<String, ShortTermMemory> _shortTerm = {};
  final Map<String, WorkingMemory> _working = {};
  final Map<String, LongTermMemory> _longTerm = {};
  Future<void> _pendingWrite = Future.value();

  Future<void> get settled => _pendingWrite;

  String shortTermStorageKey(String chatId) => '$shortTermPrefix$chatId';
  String workingStorageKey(String chatId) => '$workingPrefix$chatId';
  String longTermStorageKey(String projectId) => '$longTermPrefix$projectId';

  Future<void> load({
    required Iterable<String> chatIds,
    required Iterable<String> taskIds,
    required Iterable<String> projectIds,
  }) async {
    for (final chatId in chatIds) {
      final shortRaw = await _store.read(shortTermStorageKey(chatId));
      if (shortRaw != null) {
        _shortTerm[chatId] = ShortTermMemory.fromJson(
            jsonDecode(shortRaw) as Map<String, dynamic>);
      }
    }
    for (final taskId in taskIds) {
      final workingRaw = await _store.read(workingStorageKey(taskId));
      if (workingRaw != null) {
        _working[taskId] = WorkingMemory.fromJson(
            jsonDecode(workingRaw) as Map<String, dynamic>);
      }
    }
    for (final projectId in projectIds) {
      final raw = await _store.read(longTermStorageKey(projectId));
      if (raw != null) {
        _longTerm[projectId] =
            LongTermMemory.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    }
  }

  bool hasShortTerm(String chatId) => _shortTerm.containsKey(chatId);

  ShortTermMemory shortTermFor(String chatId) =>
      _shortTerm[chatId] ?? ShortTermMemory(chatId: chatId);

  WorkingMemory workingFor(String taskId) =>
      _working[taskId] ?? WorkingMemory(taskId: taskId);

  LongTermMemory longTermFor(String projectId) =>
      _longTerm[projectId] ?? LongTermMemory(projectId: projectId);

  void replaceMessages(String chatId, List<ChatMessage> messages) {
    final value = ShortTermMemory(
      chatId: chatId,
      messages: List.unmodifiable(messages),
    );
    _shortTerm[chatId] = value;
    _write(shortTermStorageKey(chatId), value.toJson());
  }

  void saveWorking(String taskId, String content) {
    final cleaned = content.trim();
    if (cleaned.length > 24000) {
      throw ArgumentError('Рабочая память не должна превышать 24000 символов.');
    }
    final value = WorkingMemory(taskId: taskId, content: cleaned);
    _working[taskId] = value;
    _write(workingStorageKey(taskId), value.toJson());
  }

  void saveLongTerm(String projectId, String content) {
    final cleaned = content.trim();
    if (cleaned.length > 500000) {
      throw ArgumentError(
          'Долговременная память не должна превышать 500000 символов.');
    }
    final value = LongTermMemory(projectId: projectId, content: cleaned);
    _longTerm[projectId] = value;
    _write(longTermStorageKey(projectId), value.toJson());
  }

  void rememberLongTerm(String projectId, String content) {
    final current = longTermFor(projectId).content;
    final cleaned = content.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Запись памяти не должна быть пустой.');
    }
    saveLongTerm(projectId, current.isEmpty ? cleaned : '$current\n\n$cleaned');
  }

  void clearChat(String chatId) {
    _shortTerm.remove(chatId);
    _write(
        shortTermStorageKey(chatId), ShortTermMemory(chatId: chatId).toJson());
  }

  void clearTask(String taskId) {
    _working.remove(taskId);
    _write(workingStorageKey(taskId), WorkingMemory(taskId: taskId).toJson());
  }

  void clearProject(String projectId) {
    _longTerm.remove(projectId);
    _write(longTermStorageKey(projectId),
        LongTermMemory(projectId: projectId).toJson());
  }

  void _write(String key, Map<String, Object> value) {
    final encoded = jsonEncode(value);
    _pendingWrite = _pendingWrite
        .then((_) => _store.write(key, encoded))
        .catchError((_) {});
  }
}
