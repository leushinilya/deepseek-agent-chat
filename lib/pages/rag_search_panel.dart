import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../agents/models.dart';

class RagSearchPanel extends StatefulWidget {
  const RagSearchPanel(
      {required this.rag,
      required this.client,
      required this.baseUrl,
      required this.agents,
      required this.onSaved,
      super.key});
  final Map<String, dynamic> rag;
  final http.Client client;
  final String baseUrl;
  final List<AiAgent> agents;
  final ValueChanged<Map<String, dynamic>> onSaved;

  @override
  State<RagSearchPanel> createState() => _RagSearchPanelState();
}

class _RagSearchPanelState extends State<RagSearchPanel> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _prompt;
  late final TextEditingController _candidateK;
  late final TextEditingController _resultK;
  late final TextEditingController _threshold;
  late final TextEditingController _neighborRadius;
  late final TextEditingController _maxExpansionCalls;
  late final TextEditingController _maxContextChars;
  final _compareNeighborRadius = TextEditingController(text: '0');
  final _compareExpansionCalls = TextEditingController(text: '0');
  late final TextEditingController _compareContextChars;
  final _query = TextEditingController();
  late bool _filter;
  late bool _rewrite;
  String? _agentId;
  bool _busy = false;
  bool _validatingComparison = false;
  String? _error;
  Map<String, dynamic>? _comparison;

  @override
  void initState() {
    super.initState();
    final settings = widget.rag['retrievalSettings'] as Map? ?? {};
    _prompt = TextEditingController(text: settings['prompt'] as String? ?? '');
    _candidateK =
        TextEditingController(text: '${settings['candidateK'] ?? 20}');
    _resultK = TextEditingController(text: '${settings['resultK'] ?? 5}');
    _threshold = TextEditingController(
        text: '${settings['similarityThreshold'] ?? 0.3}');
    _neighborRadius =
        TextEditingController(text: '${settings['neighborRadius'] ?? 1}');
    _maxExpansionCalls =
        TextEditingController(text: '${settings['maxExpansionCalls'] ?? 3}');
    _maxContextChars =
        TextEditingController(text: '${settings['maxContextChars'] ?? 20000}');
    _compareContextChars =
        TextEditingController(text: '${settings['maxContextChars'] ?? 20000}');
    _filter = settings['filterEnabled'] as bool? ?? true;
    _rewrite = settings['rewriteEnabled'] as bool? ?? true;
    final linked =
        widget.agents.where((agent) => agent.ragIds.contains(widget.rag['id']));
    _agentId = linked.firstOrNull?.id ?? widget.agents.firstOrNull?.id;
  }

  @override
  void dispose() {
    _prompt.dispose();
    _candidateK.dispose();
    _resultK.dispose();
    _threshold.dispose();
    _neighborRadius.dispose();
    _maxExpansionCalls.dispose();
    _maxContextChars.dispose();
    _compareNeighborRadius.dispose();
    _compareExpansionCalls.dispose();
    _compareContextChars.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String suffix, Object body,
      {bool patch = false}) async {
    final uri =
        Uri.parse('${widget.baseUrl}/api/rags/${widget.rag['id']}/$suffix');
    final response = await (patch ? widget.client.patch : widget.client.post)(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body));
    final result =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(result['error'] ?? 'Ошибка сервера RAG.');
    }
    return result;
  }

  Map<String, dynamic> _settings({bool comparison = false}) => {
        'prompt': _prompt.text.trim(),
        'filterEnabled': _filter,
        'rewriteEnabled': _rewrite,
        'candidateK': int.parse(_candidateK.text),
        'resultK': int.parse(_resultK.text),
        'similarityThreshold':
            double.parse(_threshold.text.replaceAll(',', '.')),
        'neighborRadius': int.parse(
            comparison ? _compareNeighborRadius.text : _neighborRadius.text),
        'maxExpansionCalls': int.parse(
            comparison ? _compareExpansionCalls.text : _maxExpansionCalls.text),
        'maxContextChars': int.parse(
            comparison ? _compareContextChars.text : _maxContextChars.text),
      };

  Future<void> _save() async {
    _validatingComparison = false;
    if (!_form.currentState!.validate()) return;
    final previousBudget =
        '${(widget.rag['retrievalSettings'] as Map?)?['maxContextChars'] ?? 20000}';
    final followSavedBudget = _compareContextChars.text == previousBudget;
    setState(() {
      _busy = true;
      _error = null;
      _comparison = null;
    });
    try {
      final saved = await _request('retrieval', _settings(), patch: true);
      if (!mounted) return;
      if (followSavedBudget) {
        _compareContextChars.text =
            '${(saved['retrievalSettings'] as Map)['maxContextChars']}';
      }
      widget.onSaved(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Настройки поиска сохранены')));
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compare() async {
    _validatingComparison = true;
    if (!_form.currentState!.validate()) return;
    if (_query.text.trim().isEmpty) {
      setState(() => _error = 'Введите вопрос для сравнения.');
      return;
    }
    final agent =
        widget.agents.where((agent) => agent.id == _agentId).firstOrNull;
    if (agent == null) {
      setState(() => _error = 'Выберите агента для сравнения.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _comparison = null;
    });
    try {
      final result = await _request('compare', {
        'query': _query.text.trim(),
        'provider': agent.model.providerId,
        'model': agent.model.modelId,
        'systemPrompt': agent.systemPrompt,
        'retrievalSettings': _settings(comparison: true),
      });
      if (mounted) setState(() => _comparison = result);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateComparison(String _) {
    if (_comparison != null) setState(() => _comparison = null);
  }

  String? _validateK(String? value, {bool result = false}) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 1 || number > 100) {
      return 'Введите целое число от 1 до 100';
    }
    if (result && number > (int.tryParse(_candidateK.text) ?? 0)) {
      return 'Не больше top-K до отбора';
    }
    return null;
  }

  String? _validateInteger(String? value, int min, int max) {
    final number = int.tryParse(value ?? '');
    return number == null || number < min || number > max
        ? 'Введите целое число от $min до $max'
        : null;
  }

  @override
  Widget build(BuildContext context) => Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Divider(height: 32),
        TextFormField(
            key: const Key('ragPrompt'),
            controller: _prompt,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            minLines: 3,
            maxLines: 8,
            maxLength: 10000,
            decoration: const InputDecoration(
                labelText: 'Промт RAG',
                helperText:
                    'Инструкции для ответов и работы с этой базой документов.',
                hintText:
                    'Например: цитируй пункты документа и отвечай на русском.'),
            validator: (value) => (value?.length ?? 0) > 10000
                ? 'Не больше 10000 символов'
                : null),
        const SizedBox(height: 16),
        Text('Поиск и релевантность',
            style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('ragRewriteEnabled'),
            title: const Text('Переформулировать запрос'),
            subtitle: const Text(
                'Модель выбранного агента уточнит запрос с учётом переписки.'),
            value: _rewrite,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                      _rewrite = value;
                      _comparison = null;
                    })),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('ragFilterEnabled'),
            title: const Text('Фильтр по similarity'),
            subtitle: const Text('Отбрасывать фрагменты ниже порога сходства.'),
            value: _filter,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                      _filter = value;
                      _comparison = null;
                    })),
        const SizedBox(height: 8),
        TextFormField(
            key: const Key('ragSimilarityThreshold'),
            controller: _threshold,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: const InputDecoration(
                labelText: 'Порог similarity (от −1 до 1)',
                helperText:
                    '0.3 — начальное значение. Подберите порог на своих документах.'),
            validator: (value) {
              final number =
                  double.tryParse((value ?? '').replaceAll(',', '.'));
              return number == null ||
                      !number.isFinite ||
                      number < -1 ||
                      number > 1
                  ? 'Введите число от −1 до 1'
                  : null;
            }),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragCandidateK'),
            controller: _candidateK,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Top-K до отбора',
                helperText: 'Сколько кандидатов найти в этом RAG.'),
            validator: (value) => _validateK(value)),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragResultK'),
            controller: _resultK,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Top-K после отбора',
                helperText: 'Максимум фрагментов этого RAG для ответа.'),
            validator: (value) => _validateK(value, result: true)),
        const Divider(height: 32),
        Text('Контекст раздела',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
            key: const Key('ragNeighborRadius'),
            controller: _neighborRadius,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Соседей с каждой стороны (0–2)',
                helperText: 'Добавляются после отбора релевантных фрагментов.'),
            validator: (value) => _validateInteger(value, 0, 2)),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragMaxExpansionCalls'),
            controller: _maxExpansionCalls,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Дополнительных догрузок агентом (0–5)',
                helperText:
                    'Агент может запросить продолжение того же раздела.'),
            validator: (value) => _validateInteger(value, 0, 5)),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragMaxContextChars'),
            controller: _maxContextChars,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Лимит контекста (1000–50000 символов)',
                helperText:
                    'Общий объём найденных и догруженных фрагментов этого RAG.'),
            validator: (value) => _validateInteger(value, 1000, 50000)),
        const SizedBox(height: 12),
        const Text(
            'При каждом новом сообщении выполняется поиск в RAG. Агент также может искать дополнительные сведения по ходу ответа.'),
        const SizedBox(height: 12),
        const Text(
            'Если релевантных фрагментов нет, агент сообщит о недостатке данных. Для связей между чанками перезапустите индексацию.'),
        const SizedBox(height: 12),
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
                key: const Key('ragSaveRetrieval'),
                onPressed: _busy ? null : () => _save(),
                child: const Text('Сохранить настройки поиска'))),
        const Divider(height: 32),
        Text('Сравнение качества',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Один вопрос, документы и модель: базовый поиск без фильтра и rewrite (top-5) и поиск с указанными выше параметрами. Сравнение не сохраняет настройки RAG.'),
        const SizedBox(height: 12),
        const Text('Контекст раздела для сравнения',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
            key: const Key('ragCompareNeighborRadius'),
            controller: _compareNeighborRadius,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Соседей с каждой стороны (0–2)'),
            validator: (value) =>
                _validatingComparison ? _validateInteger(value, 0, 2) : null),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragCompareExpansionCalls'),
            controller: _compareExpansionCalls,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Дополнительных догрузок агентом (0–5)'),
            validator: (value) =>
                _validatingComparison ? _validateInteger(value, 0, 5) : null),
        const SizedBox(height: 16),
        TextFormField(
            key: const Key('ragCompareContextChars'),
            controller: _compareContextChars,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Лимит контекста (1000–50000 символов)'),
            validator: (value) => _validatingComparison
                ? _validateInteger(value, 1000, 50000)
                : null),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            key: const Key('ragComparisonAgent'),
            initialValue: _agentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Агент для сравнения'),
            items: widget.agents
                .map((agent) => DropdownMenuItem(
                    value: agent.id,
                    child: Text('${agent.name} · ${agent.model.title}',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                      _agentId = value;
                      _comparison = null;
                    })),
        const SizedBox(height: 16),
        TextField(
            key: const Key('ragComparisonQuery'),
            controller: _query,
            onChanged: _invalidateComparison,
            enabled: !_busy,
            maxLength: 8000,
            minLines: 2,
            maxLines: 4,
            decoration:
                const InputDecoration(labelText: 'Вопрос для сравнения')),
        Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
                key: const Key('ragCompareButton'),
                onPressed: _busy ||
                        widget.rag['status'] != 'indexed' ||
                        widget.agents.isEmpty
                    ? null
                    : _compare,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Сравнить'))),
        if (_busy)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_comparison != null) ...[
          _result('Без фильтра и rewrite',
              _comparison!['baseline'] as Map<String, dynamic>),
          _result('С параметрами сравнения',
              _comparison!['improved'] as Map<String, dynamic>),
        ],
      ]));

  Widget _result(String title, Map<String, dynamic> result) => Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
                'Время: ${(result['durationMs'] / 1000).toStringAsFixed(1)} с · Фрагментов: ${(result['chunks'] as List).length}'),
            if (result['rewrittenQuery'] != null) ...[
              const SizedBox(height: 8),
              Text('Поисковый запрос: ${result['rewrittenQuery']}'),
            ],
            const SizedBox(height: 12),
            SelectableText(result['answer'] as String),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Найденные фрагменты и оценки'),
                children: [
                  for (final search in result['searches'] as List)
                    for (final chunk in search['candidates'] as List)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(chunk['selected'] == true
                              ? Icons.check_circle_outline
                              : Icons.remove_circle_outline),
                          title: Text(
                              '${chunk['source']} · similarity ${(chunk['score'] as num).toStringAsFixed(3)}'),
                          subtitle: Text(chunk['content'] as String)),
                ]),
          ])));
}
