import 'models.dart';

class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
        'id': id,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
        id: json['id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ShortTermMemory {
  const ShortTermMemory({
    required this.chatId,
    this.messages = const [],
  });

  final String chatId;
  final List<ChatMessage> messages;

  Map<String, Object> toJson() => {
        'chatId': chatId,
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ShortTermMemory.fromJson(Map<String, dynamic> json) =>
      ShortTermMemory(
        chatId: json['chatId'] as String,
        messages: (json['messages'] as List<dynamic>? ?? const [])
            .map((value) => ChatMessage.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class WorkingMemory {
  const WorkingMemory({required this.taskId, this.items = const []});

  final String taskId;
  final List<MemoryItem> items;

  Map<String, Object> toJson() => {
        'taskId': taskId,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory WorkingMemory.fromJson(Map<String, dynamic> json) => WorkingMemory(
        taskId: json['taskId'] as String? ?? json['chatId'] as String,
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((value) => MemoryItem.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class LongTermMemory {
  const LongTermMemory({required this.projectId, this.items = const []});

  final String projectId;
  final List<MemoryItem> items;

  Map<String, Object> toJson() => {
        'projectId': projectId,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory LongTermMemory.fromJson(Map<String, dynamic> json) => LongTermMemory(
        projectId: json['projectId'] as String? ?? json['agentId'] as String,
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((value) => MemoryItem.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}
