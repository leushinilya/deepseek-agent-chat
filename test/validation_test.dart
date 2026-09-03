import 'package:deepseek_agent_chat/comparison/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateQuery', () {
    test('trims a valid query',
        () => expect(validateQuery('  вопрос  '), 'вопрос'));
    test('rejects an empty query', () {
      expect(
          () => validateQuery('  '), throwsA(isA<InputValidationException>()));
    });
    test('rejects an oversized query', () {
      expect(() => validateQuery('x' * (maxQueryLength + 1)),
          throwsA(isA<InputValidationException>()));
    });
  });
}
