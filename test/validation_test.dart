import 'package:deepseek_agent_chat/comparison/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRoles', () {
    test('splits commas and new lines and removes blank values', () {
      expect(
        parseRoles(' учёный, , программист\n врач \r\n'),
        ['учёный', 'программист', 'врач'],
      );
    });

    test('requires a non-empty role', () {
      expect(
          () => parseRoles(' , \n '), throwsA(isA<InputValidationException>()));
    });

    test('limits the number of roles', () {
      final value =
          List.generate(maxRoles + 1, (index) => 'роль $index').join(',');
      expect(() => parseRoles(value), throwsA(isA<InputValidationException>()));
    });
  });

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
