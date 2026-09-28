import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'rag_document.dart';

Future<List<RagDocumentFile>> pickRagDocuments() async {
  final input = html.FileUploadInputElement()
    ..multiple = true
    ..accept = '.txt,.md,.markdown,.csv,.json,.pdf';
  input.click();
  await input.onChange.first;
  return [
    for (final file in input.files ?? <html.File>[])
      RagDocumentFile(file.name, file),
  ];
}

Future<Map<String, dynamic>> uploadRagDocuments(
    String baseUrl, String path, List<RagDocumentFile> files,
    {String? name}) async {
  final form = html.FormData();
  if (name != null) form.append('name', name);
  for (final file in files) {
    form.appendBlob('documents', file.nativeFile as html.File, file.name);
  }
  final request = html.HttpRequest();
  request.open('POST', '$baseUrl$path');
  final completed = request.onLoadEnd.first;
  request.send(form);
  await completed;
  if (request.status == 0) {
    throw Exception('Не удалось связаться с сервером RAG.');
  }
  final payload = jsonDecode(request.responseText ?? '{}');
  if (payload is! Map<String, dynamic>) {
    throw Exception('Сервер вернул некорректный ответ.');
  }
  if (request.status! < 200 || request.status! >= 300) {
    throw Exception(payload['error'] ?? 'Не удалось загрузить документы.');
  }
  return payload;
}
