import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

abstract interface class ComparisonGateway {
  Future<ModelResponse> fetchAnswer(String query, ModelTarget target);
  void close();
}

class ComparisonApiException implements Exception {
  const ComparisonApiException(this.message);
  final String message;
}

class ComparisonApiClient implements ComparisonGateway {
  ComparisonApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ??
            const String.fromEnvironment('API_BASE_URL',
                defaultValue: 'http://localhost:3000');

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<ModelResponse> fetchAnswer(String query, ModelTarget target) async {
    final payload =
        await _post('/api/compare', {'query': query, 'model': target.id});
    final answer = payload['answer'];
    final metrics = payload['metrics'];
    if (answer is! String ||
        answer.trim().isEmpty ||
        metrics is! Map<String, dynamic>) {
      throw const ComparisonApiException('Сервер вернул некорректный ответ.');
    }
    try {
      return ModelResponse(
        answer: normalizeAnswerText(answer),
        durationMs: (metrics['durationMs'] as num).round(),
        promptTokens: (metrics['promptTokens'] as num).round(),
        completionTokens: (metrics['completionTokens'] as num).round(),
        totalTokens: (metrics['totalTokens'] as num).round(),
        costUsd: metrics['costUsd'] == null
            ? null
            : (metrics['costUsd'] as num).toDouble(),
      );
    } catch (_) {
      throw const ComparisonApiException('Сервер вернул некорректные метрики.');
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, Object> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 3));
      final payload = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = payload['error'];
        throw ComparisonApiException(
            message is String ? message : 'Не удалось получить ответ.');
      }
      return payload;
    } on TimeoutException {
      throw const ComparisonApiException(
          'Модель слишком долго отвечает. Попробуйте ещё раз.');
    } on ComparisonApiException {
      rethrow;
    } on FormatException {
      throw const ComparisonApiException('Сервер вернул некорректный ответ.');
    } catch (_) {
      throw const ComparisonApiException(
          'Не удалось связаться с сервером. Проверьте подключение.');
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }

  @override
  void close() => _client.close();
}

String normalizeAnswerText(String value) {
  final trimmed = value.trim();
  final result = StringBuffer();
  for (var index = 0; index < trimmed.length; index++) {
    final isUnescapedSlash = trimmed.codeUnitAt(index) == 92 &&
        (index == 0 || trimmed.codeUnitAt(index - 1) != 92);
    if (isUnescapedSlash &&
        index + 3 < trimmed.length &&
        trimmed[index + 1] == 'r' &&
        trimmed.codeUnitAt(index + 2) == 92 &&
        trimmed[index + 3] == 'n') {
      result.write('\n');
      index += 3;
    } else if (isUnescapedSlash &&
        index + 1 < trimmed.length &&
        (trimmed[index + 1] == 'n' || trimmed[index + 1] == 'r')) {
      result.write('\n');
      index += 1;
    } else {
      result.write(trimmed[index]);
    }
  }
  return result.toString();
}
