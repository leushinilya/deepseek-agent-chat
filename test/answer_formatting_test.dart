import 'package:deepseek_agent_chat/comparison/comparison_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('turns escaped line separators into visible line breaks', () {
    expect(
      normalizeAnswerText(r'Первая строка\nВторая\r\nТретья'),
      'Первая строка\nВторая\nТретья',
    );
  });

  test('keeps existing line breaks and escaped backslashes', () {
    expect(
      normalizeAnswerText('Первая\nВторая' r'\\not-a-line-break'),
      'Первая\nВторая' r'\\not-a-line-break',
    );
  });
}
