import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class LlmRequest {
  const LlmRequest({required this.agent, required this.messages});
  final AiAgent agent;
  final List<ChatMessage> messages;
}

sealed class LlmEvent {
  const LlmEvent();
}

class LlmTextDelta extends LlmEvent {
  const LlmTextDelta(this.text);
  final String text;
}

class LlmDone extends LlmEvent {
  const LlmDone();
}

class LlmException implements Exception {
  const LlmException(this.message, {this.code});
  final String message;
  final String? code;
}

abstract interface class LlmOperation {
  Stream<LlmEvent> get events;
  void cancel();
}

abstract interface class LlmProvider {
  LlmOperation send(LlmRequest request);
}

class BackendLlmProvider implements LlmProvider {
  BackendLlmProvider({String? baseUrl, http.Client Function()? clientFactory})
      : _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:3000',
            ),
        _clientFactory = clientFactory ?? http.Client.new;

  final String _baseUrl;
  final http.Client Function() _clientFactory;

  @override
  LlmOperation send(LlmRequest request) {
    final client = _clientFactory();
    final controller = StreamController<LlmEvent>();
    var cancelled = false;

    Future<void> run() async {
      try {
        final httpRequest =
            http.Request('POST', Uri.parse('$_baseUrl/api/chat'))
              ..headers.addAll({
                'Content-Type': 'application/json',
                'Accept': 'application/x-ndjson',
              })
              ..body = jsonEncode({
                'provider': request.agent.model.providerId,
                'model': request.agent.model.modelId,
                'systemPrompt': request.agent.systemPrompt,
                'messages': request.messages
                    .map((message) => {
                          'role': message.role.name,
                          'content': message.content,
                        })
                    .toList(),
              });
        final response = await client.send(httpRequest).timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw const LlmException(
                'Сервер не ответил вовремя. Проверьте подключение.',
                code: 'timeout',
              ),
            );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final body = await response.stream.bytesToString();
          final payload = jsonDecode(body);
          final message = payload is Map<String, dynamic>
              ? payload['error'] as String?
              : null;
          throw LlmException(message ?? 'Не удалось получить ответ модели.');
        }
        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (cancelled || line.trim().isEmpty) continue;
          final value = jsonDecode(line);
          if (value is! Map<String, dynamic>) {
            throw const FormatException();
          }
          switch (value['type']) {
            case 'delta':
              final text = value['text'];
              if (text is! String) throw const FormatException();
              controller.add(LlmTextDelta(text));
            case 'done':
              controller.add(const LlmDone());
            case 'error':
              throw LlmException(
                value['message'] as String? ?? 'Ошибка генерации ответа.',
                code: value['code'] as String?,
              );
            default:
              throw const FormatException();
          }
        }
        if (!cancelled && !controller.isClosed) await controller.close();
      } on LlmException catch (error, stackTrace) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      } on TimeoutException catch (_, stackTrace) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(
            const LlmException(
              'Модель слишком долго отвечает. Попробуйте ещё раз.',
              code: 'timeout',
            ),
            stackTrace,
          );
          await controller.close();
        }
      } catch (_, stackTrace) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(
            const LlmException(
              'Сетевой сбой или некорректный ответ сервера.',
              code: 'network_error',
            ),
            stackTrace,
          );
          await controller.close();
        }
      } finally {
        client.close();
      }
    }

    unawaited(run());
    return _BackendLlmOperation(controller.stream, () {
      cancelled = true;
      client.close();
      if (!controller.isClosed) unawaited(controller.close());
    });
  }
}

class _BackendLlmOperation implements LlmOperation {
  _BackendLlmOperation(this.events, this._onCancel);
  @override
  final Stream<LlmEvent> events;
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}
