const maxQueryLength = 8000;

class InputValidationException implements Exception {
  const InputValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

String validateQuery(String value) {
  final query = value.trim();
  if (query.isEmpty) {
    throw const InputValidationException('Введите запрос для сравнения.');
  }
  if (query.length > maxQueryLength) {
    throw const InputValidationException(
        'Запрос не должен превышать 8000 символов.');
  }
  return query;
}
