import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

class AgentHasChatsException implements Exception {
  const AgentHasChatsException(this.chatCount);
  final int chatCount;
}

class AgentChatRepository extends ChangeNotifier {
  AgentChatRepository(this._store, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _storageKey = 'ai_agents_and_chats_v1';
  static const _schemaVersion = 1;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  final _random = Random();
  final List<AiAgent> _agents = [];
  final List<AgentChat> _chats = [];
  Future<void> _pendingWrite = Future.value();

  bool isLoaded = false;
  String? loadError;
  List<AiAgent> get agents => List.unmodifiable(_agents);
  Future<void> get settled => _pendingWrite;
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
        _chats
          ..clear()
          ..addAll((json['chats'] as List<dynamic>? ?? const [])
              .map((item) => AgentChat.fromJson(item as Map<String, dynamic>)));
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

  AgentChat createChat(String agentId) {
    if (!_agents.any((agent) => agent.id == agentId)) {
      throw StateError('Agent not found');
    }
    final now = _clock();
    final chat = AgentChat(
      id: _id('chat'),
      agentId: agentId,
      title: 'Новый чат',
      messages: const [],
      createdAt: now,
      lastActivityAt: now,
    );
    _chats.add(chat);
    _changed();
    return chat;
  }

  ChatMessage appendMessage(String chatId, ChatRole role, String content) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) throw StateError('Chat not found');
    final now = _clock();
    final message = ChatMessage(
      id: _id('message'),
      role: role,
      content: _required(content, 'Сообщение не должно быть пустым.'),
      createdAt: now,
    );
    final chat = _chats[index];
    var title = chat.title;
    if (role == ChatRole.user && chat.messages.isEmpty) {
      title = _makeTitle(message.content);
    }
    _chats[index] = chat.copyWith(
      title: title,
      messages: [...chat.messages, message],
      lastActivityAt: now,
    );
    _changed();
    return message;
  }

  void deleteChat(String id) {
    _chats.removeWhere((chat) => chat.id == id);
    _changed();
  }

  AiAgent? agentById(String id) {
    for (final agent in _agents) {
      if (agent.id == id) return agent;
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

  String _id(String prefix) =>
      '$prefix-${_clock().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

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
      'chats': _chats.map((chat) => chat.toJson()).toList(),
    });
    _pendingWrite =
        _pendingWrite.then((_) => _store.write(_storageKey, value)).catchError(
              (_) {},
            );
    await _pendingWrite;
  }
}
