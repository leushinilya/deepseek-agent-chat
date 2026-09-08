enum AgentModel {
  localGigaChat(
    id: 'local-gigachat',
    providerId: 'ollama',
    modelId: 'local-gigachat',
    title: 'GigaChat 3.1 (локальная)',
  ),
  deepseekFlash(
    id: 'deepseek-v4-flash',
    providerId: 'deepseek',
    modelId: 'deepseek-v4-flash',
    title: 'deepseek-v4-flash',
  ),
  deepseekPro(
    id: 'deepseek-v4-pro',
    providerId: 'deepseek',
    modelId: 'deepseek-v4-pro',
    title: 'deepseek-v4-pro',
  );

  const AgentModel({
    required this.id,
    required this.providerId,
    required this.modelId,
    required this.title,
  });

  final String id;
  final String providerId;
  final String modelId;
  final String title;

  static AgentModel fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    throw FormatException('Unknown agent model: $id');
  }
}

class AiAgent {
  const AiAgent({
    required this.id,
    required this.name,
    required this.systemPrompt,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String systemPrompt;
  final AgentModel model;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiAgent copyWith({
    String? name,
    String? systemPrompt,
    AgentModel? model,
    DateTime? updatedAt,
  }) =>
      AiAgent(
        id: id,
        name: name ?? this.name,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        model: model ?? this.model,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
        'model': model.id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AiAgent.fromJson(Map<String, dynamic> json) => AiAgent(
        id: json['id'] as String,
        name: json['name'] as String,
        systemPrompt: json['systemPrompt'] as String,
        model: AgentModel.fromId(json['model'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: ChatRole.values.firstWhere((role) => role.name == json['role']),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AgentChat {
  const AgentChat({
    required this.id,
    required this.agentId,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.lastActivityAt,
  });

  final String id;
  final String agentId;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastActivityAt;

  AgentChat copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? lastActivityAt,
  }) =>
      AgentChat(
        id: id,
        agentId: agentId,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        createdAt: createdAt,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'agentId': agentId,
        'title': title,
        'messages': messages.map((message) => message.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'lastActivityAt': lastActivityAt.toIso8601String(),
      };

  factory AgentChat.fromJson(Map<String, dynamic> json) => AgentChat(
        id: json['id'] as String,
        agentId: json['agentId'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List<dynamic>)
            .map((value) => ChatMessage.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      );
}
