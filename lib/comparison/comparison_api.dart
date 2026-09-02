import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

abstract interface class ComparisonGateway {
  Future<String> fetchDirect(String query);
  Future<ExplainedResult> fetchExplained(String query);
  Future<PromptedResult> fetchPrompted(String query);
  Future<List<RoleAnswer>> fetchRoles(String query, List<String> roles);
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
  Future<String> fetchDirect(String query) async {
    final data = await _request('direct', query);
    return _requiredString(data, 'answer');
  }

  @override
  Future<ExplainedResult> fetchExplained(String query) async {
    final data = await _request('explained', query);
    return ExplainedResult(
        answer: _requiredString(data, 'answer'),
        reasoningSummary: _requiredString(data, 'reasoningSummary'));
  }

  @override
  Future<PromptedResult> fetchPrompted(String query) async {
    final data = await _request('prompted', query);
    return PromptedResult(
        generatedPrompt: _requiredString(data, 'generatedPrompt'),
        answer: _requiredString(data, 'answer'));
  }

  @override
  Future<List<RoleAnswer>> fetchRoles(String query, List<String> roles) async {
    final data = await _request('roles', query, roles: roles);
    final rawAnswers = data['answers'];
    if (rawAnswers is! List) {
      throw const ComparisonApiException(
          'Сервер вернул некорректный список ответов.');
    }
    return rawAnswers.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const ComparisonApiException(
            'Сервер вернул некорректный ответ роли.');
      }
      return RoleAnswer(
          role: _requiredString(item, 'role'),
          answer: _requiredString(item, 'answer'));
    }).toList();
  }

  Future<Map<String, dynamic>> _request(String scenario, String query,
      {List<String>? roles}) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/compare/$scenario'),
            headers: {'Content-Type': 'application/json'},
            body:
                jsonEncode({'query': query, if (roles != null) 'roles': roles}),
          )
          .timeout(const Duration(seconds: 90));
      final payload = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = payload['error'];
        throw ComparisonApiException(
            message is String ? message : 'Не удалось получить ответ.');
      }
      return payload;
    } on TimeoutException {
      throw const ComparisonApiException(
          'Сервер слишком долго отвечает. Попробуйте ещё раз.');
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

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value.trim();
  }

  @override
  void close() => _client.close();
}
