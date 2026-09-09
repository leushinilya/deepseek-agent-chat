import 'dart:convert';
import 'dart:math' as math;

/// A deterministic fallback for providers that do not expose per-message usage.
/// The approximation follows the common rule of roughly four UTF-8 bytes per
/// token and always reports at least one token for non-empty text.
int estimateTokenCount(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) return 0;
  return math.max(1, (utf8.encode(normalized).length / 4).ceil());
}

String formatTokenCount(int count) {
  if (count >= 1000) {
    final value = count / 1000;
    final compact = value >= 10 || value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$compact тыс. токенов';
  }
  final mod100 = count % 100;
  final mod10 = count % 10;
  final suffix = mod100 >= 11 && mod100 <= 14
      ? 'токенов'
      : mod10 == 1
          ? 'токен'
          : mod10 >= 2 && mod10 <= 4
              ? 'токена'
              : 'токенов';
  return '$count $suffix';
}

String formatTokenNumber(int count) {
  final digits = count.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
