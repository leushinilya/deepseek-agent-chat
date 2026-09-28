import 'rag_document.dart';

Future<List<RagDocumentFile>> pickRagDocuments() async =>
    throw UnsupportedError('Выбор документов доступен в веб-версии.');

Future<Map<String, dynamic>> uploadRagDocuments(
        String baseUrl, String path, List<RagDocumentFile> files,
        {String? name}) async =>
    throw UnsupportedError('Загрузка документов доступна в веб-версии.');
