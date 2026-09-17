enum AgentModel {
  localGigaChat(
    id: 'local-gigachat',
    providerId: 'ollama',
    modelId: 'local-gigachat',
    title: 'GigaChat 3.1 (локальная)',
    contextWindowTokens: 262144,
  ),
  deepseekFlash(
    id: 'deepseek-v4-flash',
    providerId: 'deepseek',
    modelId: 'deepseek-v4-flash',
    title: 'deepseek-v4-flash',
    contextWindowTokens: 1000000,
  ),
  deepseekPro(
    id: 'deepseek-v4-pro',
    providerId: 'deepseek',
    modelId: 'deepseek-v4-pro',
    title: 'deepseek-v4-pro',
    contextWindowTokens: 1000000,
  );

  const AgentModel({
    required this.id,
    required this.providerId,
    required this.modelId,
    required this.title,
    required this.contextWindowTokens,
  });

  final String id;
  final String providerId;
  final String modelId;
  final String title;
  final int contextWindowTokens;

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

enum ContextStrategy {
  fullHistory,
  compression,
  slidingWindow,
  stickyFacts,
  branching;

  static ContextStrategy fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return ContextStrategy.fullHistory;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.tokenCount,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final int? tokenCount;

  Map<String, Object> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        if (tokenCount != null) 'tokenCount': tokenCount!,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: ChatRole.values.firstWhere((role) => role.name == json['role']),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        tokenCount: json['tokenCount'] as int?,
      );
}

class ChatBranch {
  const ChatBranch({
    required this.id,
    required this.name,
    required this.messages,
  });

  final String id;
  final String name;
  final List<ChatMessage> messages;

  ChatBranch copyWith({String? name, List<ChatMessage>? messages}) =>
      ChatBranch(
        id: id,
        name: name ?? this.name,
        messages: messages ?? this.messages,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ChatBranch.fromJson(Map<String, dynamic> json) => ChatBranch(
        id: json['id'] as String,
        name: json['name'] as String,
        messages: (json['messages'] as List<dynamic>? ?? const [])
            .map((value) => ChatMessage.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class ProjectInvariant {
  const ProjectInvariant({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };

  factory ProjectInvariant.fromJson(Map<String, dynamic> json) =>
      ProjectInvariant(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );
}

class AgentProject {
  const AgentProject({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.stateModelId,
    this.invariants = const [],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? stateModelId;
  final List<ProjectInvariant> invariants;

  AgentProject copyWith({
    String? title,
    DateTime? updatedAt,
    String? stateModelId,
    List<ProjectInvariant>? invariants,
  }) =>
      AgentProject(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        stateModelId: stateModelId ?? this.stateModelId,
        invariants: invariants ?? this.invariants,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        if (stateModelId != null) 'stateModelId': stateModelId!,
        'invariants': invariants.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentProject.fromJson(Map<String, dynamic> json) => AgentProject(
        id: json['id'] as String,
        title: json['title'] as String,
        stateModelId: json['stateModelId'] as String?,
        invariants: (json['invariants'] as List<dynamic>? ?? const [])
            .map((item) =>
                ProjectInvariant.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class TaskStateDefinition {
  const TaskStateDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.colorValue,
  });

  final String id;
  final String name;
  final String description;
  final int colorValue;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'colorValue': colorValue,
      };

  factory TaskStateDefinition.fromJson(Map<String, dynamic> json) =>
      TaskStateDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        colorValue: json['colorValue'] as int,
      );
}

class TaskStateModel {
  const TaskStateModel({
    required this.id,
    required this.title,
    required this.states,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<TaskStateDefinition> states;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskStateModel copyWith({
    String? title,
    List<TaskStateDefinition>? states,
    DateTime? updatedAt,
  }) =>
      TaskStateModel(
        id: id,
        title: title ?? this.title,
        states: states ?? this.states,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'states': states.map((state) => state.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TaskStateModel.fromJson(Map<String, dynamic> json) => TaskStateModel(
        id: json['id'] as String,
        title: json['title'] as String,
        states: (json['states'] as List<dynamic>? ?? const [])
            .map((value) =>
                TaskStateDefinition.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class TaskStageResult {
  const TaskStageResult({
    required this.stateId,
    required this.stateName,
    required this.result,
    required this.completedAt,
  });

  final String stateId;
  final String stateName;
  final String result;
  final DateTime completedAt;

  Map<String, Object> toJson() => {
        'stateId': stateId,
        'stateName': stateName,
        'result': result,
        'completedAt': completedAt.toIso8601String(),
      };

  factory TaskStageResult.fromJson(Map<String, dynamic> json) =>
      TaskStageResult(
        stateId: json['stateId'] as String,
        stateName: json['stateName'] as String,
        result: json['result'] as String,
        completedAt: DateTime.parse(json['completedAt'] as String),
      );
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.currentStateId,
    this.stageResults = const [],
    this.agentId,
  });

  final String id;
  final String projectId;
  final String title;
  final String? agentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? currentStateId;
  final List<TaskStageResult> stageResults;

  AgentTask copyWith({
    String? title,
    Object? agentId = _unset,
    DateTime? updatedAt,
    Object? currentStateId = _unset,
    List<TaskStageResult>? stageResults,
  }) =>
      AgentTask(
        id: id,
        projectId: projectId,
        title: title ?? this.title,
        agentId: identical(agentId, _unset) ? this.agentId : agentId as String?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        currentStateId: identical(currentStateId, _unset)
            ? this.currentStateId
            : currentStateId as String?,
        stageResults: stageResults ?? this.stageResults,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        if (agentId != null) 'agentId': agentId!,
        if (currentStateId != null) 'currentStateId': currentStateId!,
        'stageResults': stageResults.map((result) => result.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentTask.fromJson(Map<String, dynamic> json) => AgentTask(
        id: json['id'] as String,
        projectId: json['projectId'] as String? ?? json['agentId'] as String,
        title: json['title'] as String,
        agentId: json['agentId'] as String?,
        currentStateId: json['currentStateId'] as String?,
        stageResults: (json['stageResults'] as List<dynamic>? ?? const [])
            .map((value) =>
                TaskStageResult.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

const _unset = Object();

class AgentChat {
  const AgentChat({
    required this.id,
    required this.agentId,
    required this.taskId,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.lastActivityAt,
    this.compressionMax = 20,
    this.compressionMin = 6,
    this.contextSummary = '',
    this.summarizedMessageCount = 0,
    this.contextStrategy = ContextStrategy.fullHistory,
    this.windowSize = 12,
    this.facts = const {},
    this.branches = const [],
    this.activeBranchId,
    this.checkpointMessageCount,
  });

  final String id;
  final String agentId;
  final String taskId;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  bool get compressionEnabled => contextStrategy == ContextStrategy.compression;
  final int compressionMax;
  final int compressionMin;
  final String contextSummary;
  final int summarizedMessageCount;

  final ContextStrategy contextStrategy;
  final int windowSize;
  final Map<String, String> facts;
  final List<ChatBranch> branches;
  final String? activeBranchId;
  final int? checkpointMessageCount;

  List<ChatMessage> get contextMessages {
    switch (contextStrategy) {
      case ContextStrategy.compression:
        return messages.skip(summarizedMessageCount).toList(growable: false);
      case ContextStrategy.slidingWindow:
      case ContextStrategy.stickyFacts:
        final start =
            messages.length > windowSize ? messages.length - windowSize : 0;
        return messages.sublist(start);
      case ContextStrategy.fullHistory:
      case ContextStrategy.branching:
        return messages;
    }
  }

  String get activeSummary {
    if (contextStrategy == ContextStrategy.compression) return contextSummary;
    if (contextStrategy == ContextStrategy.stickyFacts && facts.isNotEmpty) {
      return facts.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
    return '';
  }

  AgentChat copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? lastActivityAt,
    int? compressionMax,
    int? compressionMin,
    String? contextSummary,
    int? summarizedMessageCount,
    ContextStrategy? contextStrategy,
    int? windowSize,
    Map<String, String>? facts,
    List<ChatBranch>? branches,
    String? activeBranchId,
    int? checkpointMessageCount,
  }) =>
      AgentChat(
        id: id,
        agentId: agentId,
        taskId: taskId,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        createdAt: createdAt,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        compressionMax: compressionMax ?? this.compressionMax,
        compressionMin: compressionMin ?? this.compressionMin,
        contextSummary: contextSummary ?? this.contextSummary,
        summarizedMessageCount:
            summarizedMessageCount ?? this.summarizedMessageCount,
        contextStrategy: contextStrategy ?? this.contextStrategy,
        windowSize: windowSize ?? this.windowSize,
        facts: facts ?? this.facts,
        branches: branches ?? this.branches,
        activeBranchId: activeBranchId ?? this.activeBranchId,
        checkpointMessageCount:
            checkpointMessageCount ?? this.checkpointMessageCount,
      );

  Map<String, Object> toJson({bool includeMessages = true}) => {
        'id': id,
        'agentId': agentId,
        'taskId': taskId,
        'title': title,
        if (includeMessages)
          'messages': messages.map((message) => message.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'lastActivityAt': lastActivityAt.toIso8601String(),
        'compressionEnabled': compressionEnabled,
        'compressionMax': compressionMax,
        'compressionMin': compressionMin,
        'contextSummary': contextSummary,
        'summarizedMessageCount': summarizedMessageCount,
        'contextStrategy': contextStrategy.name,
        'windowSize': windowSize,
        'facts': facts,
        'branches': branches.map((branch) => branch.toJson()).toList(),
        if (activeBranchId != null) 'activeBranchId': activeBranchId!,
        if (checkpointMessageCount != null)
          'checkpointMessageCount': checkpointMessageCount!,
      };

  factory AgentChat.fromJson(Map<String, dynamic> json) => AgentChat(
        id: json['id'] as String,
        agentId: json['agentId'] as String,
        taskId: json['taskId'] as String? ?? json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List<dynamic>? ?? const [])
            .map((value) => ChatMessage.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
        compressionMax: json['compressionMax'] as int? ?? 20,
        compressionMin: json['compressionMin'] as int? ?? 6,
        contextSummary: json['contextSummary'] as String? ?? '',
        summarizedMessageCount: json['summarizedMessageCount'] as int? ?? 0,
        contextStrategy: json.containsKey('contextStrategy')
            ? ContextStrategy.fromName(json['contextStrategy'] as String?)
            : (json['compressionEnabled'] as bool? ?? false)
                ? ContextStrategy.compression
                : ContextStrategy.fullHistory,
        windowSize: json['windowSize'] as int? ?? 12,
        facts: (json['facts'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value.toString())),
        branches: (json['branches'] as List<dynamic>? ?? const [])
            .map((value) => ChatBranch.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        activeBranchId: json['activeBranchId'] as String?,
        checkpointMessageCount: json['checkpointMessageCount'] as int?,
      );
}
