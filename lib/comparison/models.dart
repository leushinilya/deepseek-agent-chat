enum ModelTarget {
  gigaChat('local-gigachat', 'GigaChat 3.1', 'Локальная модель', false),
  deepseekFlash('deepseek-v4-flash', 'DeepSeek V4 Flash', 'DeepSeek API', true),
  deepseekPro('deepseek-v4-pro', 'DeepSeek V4 Pro', 'DeepSeek API', true);

  const ModelTarget(this.id, this.title, this.provider, this.isPaid);

  final String id;
  final String title;
  final String provider;
  final bool isPaid;
}

class ModelResponse {
  const ModelResponse(
      {required this.answer,
      required this.durationMs,
      required this.promptTokens,
      required this.completionTokens,
      required this.totalTokens,
      this.costUsd});

  final String answer;
  final int durationMs;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double? costUsd;
}

class ModelUpdate {
  const ModelUpdate({required this.target, this.value, this.error});

  final ModelTarget target;
  final ModelResponse? value;
  final String? error;
}
