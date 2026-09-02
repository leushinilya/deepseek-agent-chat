const maxQueryLength = 8000;
const maxRoles = 10;
const maxRoleLength = 80;

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

List<String> parseRoles(String value) {
  final roles = value
      .split(RegExp(r'[,\n\r]+'))
      .map((role) => role.trim())
      .where((role) => role.isNotEmpty)
      .toList();
  if (roles.isEmpty) {
    throw const InputValidationException('Укажите хотя бы одну роль.');
  }
  if (roles.length > maxRoles) {
    throw const InputValidationException('Можно указать не более 10 ролей.');
  }
  if (roles.any((role) => role.length > maxRoleLength)) {
    throw const InputValidationException(
        'Название каждой роли не должно превышать 80 символов.');
  }
  return roles;
}
