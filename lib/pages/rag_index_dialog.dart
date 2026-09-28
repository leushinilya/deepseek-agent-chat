import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RagIndexDialog extends StatefulWidget {
  const RagIndexDialog({
    required this.ragId,
    required this.ragName,
    this.client,
    super.key,
  });

  final String ragId;
  final String ragName;
  final http.Client? client;

  @override
  State<RagIndexDialog> createState() => _RagIndexDialogState();
}

class _RagIndexDialogState extends State<RagIndexDialog> {
  static const _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:3000');
  static const _pageSize = 10;
  late final http.Client _client = widget.client ?? http.Client();
  List<Map<String, dynamic>> _chunks = [];
  int _offset = 0;
  int _total = 0;
  int _requestNumber = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load(int offset) async {
    final requestNumber = ++_requestNumber;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_baseUrl/api/rags/${widget.ragId}/chunks')
          .replace(queryParameters: {
        'offset': '$offset',
        'limit': '$_pageSize',
      });
      final response = await _client.get(uri);
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || payload is! Map<String, dynamic>) {
        throw Exception(payload is Map
            ? payload['error'] ?? 'Не удалось загрузить индекс.'
            : 'Не удалось загрузить индекс.');
      }
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _chunks = (payload['chunks'] as List).cast<Map<String, dynamic>>();
        _offset = offset;
        _total = payload['total'] as int;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Локальный индекс: ${widget.ragName}'),
        content: SizedBox(
          width: 760,
          height: 540,
          child: Column(children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Сохранённые чанки, эмбеддинги и метаданные'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                              TextButton(
                                onPressed: () => _load(_offset),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        )
                      : _chunks.isEmpty
                          ? const Center(
                              child: Text(
                                  'Индекс пуст. Запустите индексацию документов.'),
                            )
                          : ListView.builder(
                              itemCount: _chunks.length,
                              itemBuilder: (context, index) =>
                                  _chunkTile(_chunks[index]),
                            ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(_total == 0
                    ? '0 чанков'
                    : 'Чанки ${_offset + 1}–${_offset + _chunks.length} из $_total'),
              ),
              IconButton(
                key: const Key('ragIndexPreviousPage'),
                tooltip: 'Предыдущая страница',
                onPressed: _loading || _offset == 0
                    ? null
                    : () => _load((_offset - _pageSize).clamp(0, _total)),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const Key('ragIndexNextPage'),
                tooltip: 'Следующая страница',
                onPressed: _loading || _offset + _chunks.length >= _total
                    ? null
                    : () => _load(_offset + _pageSize),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      );

  Widget _chunkTile(Map<String, dynamic> chunk) {
    final embedding = chunk['embedding'] as List;
    final section = chunk['section'] as String?;
    return Card(
      child: ExpansionTile(
        key: Key('ragChunk-${chunk['chunkId']}'),
        title: Text('${chunk['source']} · ${section ?? 'Без раздела'}'),
        subtitle: Text('chunk_id: ${chunk['chunkId']}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('source: ${chunk['source']}'),
                SelectableText('title/file: ${chunk['title']}'),
                SelectableText('section: ${section ?? '—'}'),
                SelectableText('chunk_id: ${chunk['chunkId']}'),
                const SizedBox(height: 10),
                const Text('Текст чанка',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                SelectableText(chunk['content'] as String),
                const SizedBox(height: 10),
                TextButton.icon(
                  key: Key('ragEmbedding-${chunk['chunkId']}'),
                  onPressed: () => _showEmbedding(chunk),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Размерность эмбеддинга: ${embedding.length}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEmbedding(Map<String, dynamic> chunk) {
    final embedding = chunk['embedding'] as List;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Эмбеддинг чанка'),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('chunk_id: ${chunk['chunkId']}'),
              Text('Размерность: ${embedding.length}'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(jsonEncode(embedding)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}
