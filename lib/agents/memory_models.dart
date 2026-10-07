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
  const WorkingMemory({required this.taskId, this.content = ''});

  final String taskId;
  final String content;

  Map<String, Object> toJson() => {
        'taskId': taskId,
        'content': content,
      };

  factory WorkingMemory.fromJson(Map<String, dynamic> json) {
    final legacyItems = (json['items'] as List<dynamic>? ?? const [])
        .map((value) => MemoryItem.fromJson(value as Map<String, dynamic>))
        .map((item) => item.content)
        .where((content) => content.trim().isNotEmpty);
    return WorkingMemory(
      taskId: json['taskId'] as String? ?? json['chatId'] as String,
      content: json['content'] as String? ?? legacyItems.join('\n\n'),
    );
  }
}

class LongTermMemory {
  const LongTermMemory({required this.projectId, this.content = ''});

  final String projectId;
  final String content;

  List<String> get promptMessages => content.isEmpty ? const [] : [content];

  Map<String, Object> toJson() => {
        'projectId': projectId,
        'content': content,
      };

  factory LongTermMemory.fromJson(Map<String, dynamic> json) => LongTermMemory(
        projectId: json['projectId'] as String? ?? json['agentId'] as String,
        content: json['content'] as String? ??
            (json['items'] as List<dynamic>? ?? const [])
                .map((value) =>
                    (value as Map<String, dynamic>)['content'] as String)
                .where((content) => content.trim().isNotEmpty)
                .join('\n\n'),
      );
}
