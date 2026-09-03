import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

abstract interface class ComparisonGateway {
  Future<String> fetchAnswer(String query, double temperature);
  Future<ComparisonEvaluation> evaluate(
    String query,
    Map<ComparisonVariant, String> answers,
  );
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
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:3000',
            );

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<String> fetchAnswer(String query, double temperature) async {
    final payload = await _post('/api/compare', {
      'query': query,
      'temperature': temperature,
    });
    final answer = payload['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const ComparisonApiException('Сервер вернул некорректный ответ.');
    }
    return answer.trim();
  }

  @override
  Future<ComparisonEvaluation> evaluate(
    String query,
    Map<ComparisonVariant, String> answers,
  ) async {
    final groups = <Map<String, Object>>[];
    for (final temperature in [0.0, 0.7, 1.2]) {
      groups.add({
        'temperature': temperature,
        'answers': [
          for (final variant in ComparisonVariant.values)
            if (variant.temperature == temperature) answers[variant]!,
        ],
      });
    }
    final payload = await _post('/api/evaluate', {
      'query': query,
      'groups': groups,
    });
    final rawItems = payload['evaluations'];
    if (rawItems is! List || rawItems.length != 3) {
      throw const ComparisonApiException('Сервер вернул некорректную оценку.');
    }
    try {
      return ComparisonEvaluation(
        items: rawItems.map((raw) {
          final item = raw as Map<String, dynamic>;
          return TemperatureEvaluation(
            temperature: (item['temperature'] as num).toDouble(),
            accuracy: item['accuracy'] as int,
            creativity: item['creativity'] as int,
            diversity: item['diversity'] as int,
            summary: (item['summary'] as String).trim(),
          );
        }).toList(),
      );
    } catch (_) {
      throw const ComparisonApiException('Сервер вернул некорректную оценку.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      final payload = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = payload['error'];
        throw ComparisonApiException(
          message is String ? message : 'Не удалось получить ответ.',
        );
      }
      return payload;
    } on TimeoutException {
      throw const ComparisonApiException(
        'Сервер слишком долго отвечает. Попробуйте ещё раз.',
      );
    } on ComparisonApiException {
      rethrow;
    } on FormatException {
      throw const ComparisonApiException('Сервер вернул некорректный ответ.');
    } catch (_) {
      throw const ComparisonApiException(
        'Не удалось связаться с сервером. Проверьте подключение.',
      );
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
