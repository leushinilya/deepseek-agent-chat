import 'package:deepseek_agent_chat/agents/token_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimates empty and non-empty text deterministically', () {
    expect(estimateTokenCount(''), 0);
    expect(estimateTokenCount('test'), 1);
    expect(estimateTokenCount('Привет'), greaterThan(1));
  });

  test('formats token counts with Russian plurals and compact thousands', () {
    expect(formatTokenCount(0), '0 токенов');
    expect(formatTokenCount(1), '1 токен');
    expect(formatTokenCount(22), '22 токена');
    expect(formatTokenCount(1200), '1,2 тыс. токенов');
    expect(formatTokenNumber(1000000), '1 000 000');
  });
}
