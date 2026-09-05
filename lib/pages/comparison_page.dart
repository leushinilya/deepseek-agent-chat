import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../comparison/comparison_api.dart';
import '../comparison/comparison_runner.dart';
import '../comparison/models.dart';
import '../comparison/validation.dart';

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({super.key});

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  final _queryController = TextEditingController();
  final _queryFocus = FocusNode();
  late final ComparisonRunner _runner =
      ComparisonRunner(() => ComparisonApiClient());
  final _states = <ModelTarget, _ResultState>{
    for (final target in ModelTarget.values) target: const _ResultState(),
  };
  final _selected = <ModelTarget, bool>{
    for (final target in ModelTarget.values) target: true,
  };
  String? _queryError;

  bool get _isRunning => _states.values.any((state) => state.loading);
  bool get _hasResults =>
      _states.values.any((state) => state.value != null || state.error != null);

  @override
  void dispose() {
    _runner.dispose();
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _runComparison() async {
    String query;
    setState(() => _queryError = null);
    try {
      query = validateQuery(_queryController.text);
    } on InputValidationException catch (error) {
      setState(() => _queryError = error.message);
      _queryFocus.requestFocus();
      return;
    }
    final selectedTargets = ModelTarget.values
        .where((target) => _selected[target]!)
        .toList(growable: false);
    if (selectedTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну модель.')),
      );
      return;
    }
    setState(() {
      for (final target in ModelTarget.values) {
        _states[target] = _selected[target]!
            ? const _ResultState(loading: true)
            : const _ResultState();
      }
    });
    await _runner.run(
      query: query,
      targets: selectedTargets,
      onUpdate: _applyUpdate,
    );
  }

  void _setSelected(ModelTarget target, bool value) {
    setState(() {
      _selected[target] = value;
      _states[target] = const _ResultState();
    });
  }

  void _applyUpdate(ModelUpdate update) {
    if (!mounted) return;
    setState(() => _states[update.target] =
        _ResultState(value: update.value, error: update.error));
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Ответ скопирован'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildComposer(),
                        const SizedBox(height: 24),
                        _buildResults(),
                        const SizedBox(height: 24),
                        _buildSummary(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: const Color(0xFF3659D9),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.compare_arrows_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Сравнение моделей',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    const Text('Один запрос — три независимых ответа',
                        style: TextStyle(color: Color(0xFF667085))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('queryField'),
            controller: _queryController,
            focusNode: _queryFocus,
            minLines: 4,
            maxLines: null,
            maxLength: maxQueryLength,
            decoration: InputDecoration(
              labelText: 'Запрос',
              alignLabelWithHint: true,
              hintText:
                  'Например: объясни простыми словами, как работает квантовый компьютер',
              errorText: _queryError,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('runButton'),
              onPressed: _runComparison,
              icon: Icon(_isRunning
                  ? Icons.refresh_rounded
                  : Icons.auto_awesome_rounded),
              label: Text(_isRunning ? 'Запустить заново' : 'Получить ответы'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 18.0;
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 700
                ? 2
                : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final target in ModelTarget.values)
              SizedBox(
                width: width,
                child: _AnswerCard(
                  target: target,
                  state: _states[target]!,
                  selected: _selected[target]!,
                  onSelected: _isRunning
                      ? null
                      : (value) => _setSelected(target, value),
                  onCopy: _copy,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummary() {
    return _Surface(
      key: const Key('summarySection'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.query_stats_rounded, color: Color(0xFF3659D9)),
              const SizedBox(width: 10),
              Text('Итоги', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Фактические показатели последнего запуска',
              style: TextStyle(color: Color(0xFF667085))),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final stacked = constraints.maxWidth < 780;
              final width = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap * 2) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final target in ModelTarget.values)
                    SizedBox(
                        width: width,
                        child: _SummaryCard(
                          target: target,
                          state: _states[target]!,
                          selected: _selected[target]!,
                        )),
                ],
              );
            },
          ),
          if (!_hasResults && !_isRunning) ...[
            const SizedBox(height: 16),
            const Text('Метрики появятся после получения ответов.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A8496))),
          ],
        ],
      ),
    );
  }
}

class _ResultState {
  const _ResultState({this.value, this.error, this.loading = false});
  final ModelResponse? value;
  final String? error;
  final bool loading;
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E6EF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A162033), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: child,
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.target,
    required this.state,
    required this.selected,
    required this.onSelected,
    required this.onCopy,
  });
  final ModelTarget target;
  final _ResultState state;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE2ED))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading)
            const LinearProgressIndicator(minHeight: 3)
          else
            const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: target == ModelTarget.gigaChat
                          ? const Color(0xFFEAF8F1)
                          : const Color(0xFFE8EDFF),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                      target == ModelTarget.gigaChat
                          ? Icons.computer_rounded
                          : Icons.cloud_outlined,
                      color: target == ModelTarget.gigaChat
                          ? const Color(0xFF16794B)
                          : const Color(0xFF3659D9),
                      size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(target.title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF172033))),
                      Text(target.provider,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF7A8496))),
                    ],
                  ),
                ),
                Tooltip(
                  message: selected
                      ? 'Исключить ${target.title}'
                      : 'Добавить ${target.title}',
                  child: Checkbox(
                    key: Key('model-checkbox-${target.id}'),
                    value: selected,
                    onChanged: onSelected == null
                        ? null
                        : (value) => onSelected!(value ?? false),
                    visualDensity: VisualDensity.compact,
                    semanticLabel: 'Использовать ${target.title}',
                  ),
                ),
                if (selected && state.value != null)
                  IconButton(
                      onPressed: () => onCopy(state.value!.answer),
                      tooltip: 'Копировать ответ',
                      icon: const Icon(Icons.copy_rounded, size: 18)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE9EDF4)),
          SizedBox(
            height: 316,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Semantics(
                  key: ValueKey('answer-body-${target.id}-$selected'),
                  liveRegion: true,
                  label: state.loading
                      ? '${target.title} загружается'
                      : target.title,
                  child: _body()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (!selected) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 92),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.remove_circle_outline_rounded,
                color: Color(0xFFABB4C5), size: 28),
            SizedBox(height: 10),
            Text(
              'Модель не участвует в обработке',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF7A8496)),
            ),
          ]),
        ),
      );
    }
    if (state.error != null) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFB42318), size: 20),
        const SizedBox(width: 9),
        Expanded(
            child: Text(state.error!,
                style: const TextStyle(color: Color(0xFF912018), height: 1.4))),
      ]);
    }
    if (state.value != null) {
      return SelectableText(state.value!.answer,
          style: const TextStyle(
              fontSize: 15, height: 1.55, color: Color(0xFF253047)));
    }
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 92),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(height: 12),
          Text('Формируем ответ…', style: TextStyle(color: Color(0xFF667085))),
        ])),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 92),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notes_rounded, color: Color(0xFFABB4C5), size: 28),
        SizedBox(height: 10),
        Text('Здесь появится ответ',
            style: TextStyle(color: Color(0xFF7A8496))),
      ])),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.target,
    required this.state,
    required this.selected,
  });
  final ModelTarget target;
  final _ResultState state;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final value = state.value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(target.title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF172033))),
          const SizedBox(height: 13),
          _MetricRow(
              icon: Icons.schedule_rounded,
              label: 'Время ответа',
              value: value == null
                  ? _placeholder
                  : _formatDuration(value.durationMs)),
          const SizedBox(height: 9),
          _MetricRow(
              icon: Icons.data_usage_rounded,
              label: 'Токены',
              value: value == null
                  ? _placeholder
                  : '${value.totalTokens} (${value.promptTokens} + ${value.completionTokens})'),
          const SizedBox(height: 9),
          _MetricRow(
              icon: Icons.payments_outlined,
              label: 'Стоимость',
              value: value == null
                  ? _placeholder
                  : value.costUsd == null
                      ? 'Бесплатно'
                      : '\$${value.costUsd!.toStringAsFixed(6)}'),
        ],
      ),
    );
  }

  String get _placeholder => state.loading
      ? 'Считаем…'
      : !selected
          ? 'Не участвует'
          : state.error != null
              ? 'Недоступно'
              : '—';

  static String _formatDuration(int milliseconds) {
    if (milliseconds < 1000) return '$milliseconds мс';
    return '${(milliseconds / 1000).toStringAsFixed(2)} с';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF667085)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(label,
              style: const TextStyle(color: Color(0xFF475467), fontSize: 13))),
      const SizedBox(width: 8),
      Text(value,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF253047),
              fontSize: 13)),
    ]);
  }
}
