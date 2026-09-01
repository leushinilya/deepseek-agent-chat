import 'package:deepseek_agent_chat/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ResponseSettings serializes backend defaults', () {
    expect(const ResponseSettings().toJson(), {
      'responseFormat': 'freeform',
      'maxTokens': 1000,
      'stopSequence': null,
    });
  });

  test('ResponseSettings updates values without affecting other fields', () {
    const initial = ResponseSettings(stopSequence: 'END');
    final updated = initial.copyWith(
      responseFormat: ResponseFormat.json,
      maxTokens: 2000,
      clearStopSequence: true,
    );

    expect(updated.responseFormat, ResponseFormat.json);
    expect(updated.maxTokens, 2000);
    expect(updated.stopSequence, isNull);
  });

  test('ChatMessage pretty-prints JSON responses for display', () {
    const message = ChatMessage(
      role: 'assistant',
      content: '{"status":"ok","items":[1,2]}',
      responseFormat: ResponseFormat.json,
    );

    expect(
      message.displayContent,
      '{\n  "status": "ok",\n  "items": [\n    1,\n    2\n  ]\n}',
    );
    expect(message.toJson()['content'], '{"status":"ok","items":[1,2]}');
  });

  test('ChatMessage leaves freeform and invalid JSON unchanged', () {
    const freeform = ChatMessage(role: 'assistant', content: '{"status":"ok"}');
    const invalidJson = ChatMessage(
      role: 'assistant',
      content: 'not json',
      responseFormat: ResponseFormat.json,
    );

    expect(freeform.displayContent, '{"status":"ok"}');
    expect(invalidJson.displayContent, 'not json');
  });
}
