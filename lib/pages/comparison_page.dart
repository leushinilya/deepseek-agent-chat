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
  static const _temperatures = [0.0, 0.7, 1.2];

  final _queryController = TextEditingController();
  final _queryFocus = FocusNode();
  late final ComparisonRunner _runner =
      ComparisonRunner(() => ComparisonApiClient());
  final _states = <ComparisonVariant, _ResultState>{
    for (final variant in ComparisonVariant.values)
      variant: const _ResultState(),
  };
  String? _queryError;
  _EvaluationState _evaluationState = const _EvaluationState();

  bool get _isRunning =>
      _states.values.any((state) => state.loading) || _evaluationState.loading;

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

    setState(() {
      for (final variant in ComparisonVariant.values) {
        _states[variant] = const _ResultState(loading: true);
      }
      _evaluationState = const _EvaluationState(loading: true);
    });
    await _runner.run(
      query: query,
      onUpdate: _applyUpdate,
      onEvaluation: _applyEvaluation,
    );
  }

  void _applyEvaluation(EvaluationUpdate update) {
    if (!mounted) return;
    setState(() {
      _evaluationState = _EvaluationState(
        value: update.value,
        error: update.error,
      );
    });
  }

  void _applyUpdate(VariantUpdate update) {
    if (!mounted) return;
    setState(() {
      _states[update.variant] = _ResultState(
        value: update.value,
        error: update.error,
      );
    });
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ответ скопирован'),
        duration: Duration(seconds: 2),
      ),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
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
                        _buildEvaluation(),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.thermostat_rounded, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Сравнение температур DeepSeek',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Один запрос — девять независимых вариантов ответа',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E6EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A162033),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('queryField'),
            controller: _queryController,
            focusNode: _queryFocus,
            minLines: 4,
            maxLines: 8,
            maxLength: maxQueryLength,
            decoration: InputDecoration(
              labelText: 'Запрос',
              alignLabelWithHint: true,
              hintText:
                  'Например: составь план подготовки к техническому собеседованию',
              errorText: _queryError,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: _isRunning
                  ? 'Перезапустить сравнение и отменить текущие запросы'
                  : 'Получить девять ответов',
              child: FilledButton.icon(
                key: const Key('runButton'),
                onPressed: _runComparison,
                icon: Icon(
                  _isRunning
                      ? Icons.refresh_rounded
                      : Icons.auto_awesome_rounded,
                ),
                label: Text(
                  _isRunning ? 'Запустить заново' : 'Получить ответы',
                ),
              ),
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
        final wide = constraints.maxWidth >= 1050;
        final columnWidth =
            wide ? (constraints.maxWidth - gap * 2) / 3 : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final temperature in _temperatures)
              SizedBox(
                width: columnWidth,
                child: _TemperatureColumn(
                  temperature: temperature,
                  variants: ComparisonVariant.values
                      .where((item) => item.temperature == temperature)
                      .toList(),
                  states: _states,
                  onCopy: _copy,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEvaluation() {
    return Container(
      key: const Key('evaluationSection'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF3659D9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Итоговая оценка',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Средняя оценка трёх вариантов для каждой температуры · шкала от 1 до 10',
            style: TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_evaluationState.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Дождитесь всех ответов — затем модель сравнит результаты',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            )
          else if (_evaluationState.error != null)
            _EvaluationError(message: _evaluationState.error!)
          else if (_evaluationState.value != null)
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 14.0;
                final wide = constraints.maxWidth >= 900;
                final width = wide
                    ? (constraints.maxWidth - gap * 2) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in _evaluationState.value!.items)
                      SizedBox(
                        width: width,
                        child: _EvaluationCard(item: item),
                      ),
                  ],
                );
              },
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Оценка появится после получения всех девяти ответов.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A8496)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultState {
  const _ResultState({this.value, this.error, this.loading = false});

  final String? value;
  final String? error;
  final bool loading;
}

class _EvaluationState {
  const _EvaluationState({this.value, this.error, this.loading = false});

  final ComparisonEvaluation? value;
  final String? error;
  final bool loading;
}

class _EvaluationCard extends StatelessWidget {
  const _EvaluationCard({required this.item});

  final TemperatureEvaluation item;

  String get _temperatureLabel =>
      item.temperature == 0 ? '0' : '${item.temperature}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Temperature: $_temperatureLabel',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172033),
            ),
          ),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Точность', score: item.accuracy),
          const SizedBox(height: 9),
          _ScoreRow(label: 'Креативность', score: item.creativity),
          const SizedBox(height: 9),
          _ScoreRow(label: 'Разнообразие', score: item.diversity),
          const SizedBox(height: 14),
          Text(
            item.summary,
            style: const TextStyle(
              color: Color(0xFF475467),
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF344054),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$score / 10',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF2949BE),
            ),
          ),
        ),
      ],
    );
  }
}

class _EvaluationError extends StatelessWidget {
  const _EvaluationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF912018)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemperatureColumn extends StatelessWidget {
  const _TemperatureColumn({
    required this.temperature,
    required this.variants,
    required this.states,
    required this.onCopy,
  });

  final double temperature;
  final List<ComparisonVariant> variants;
  final Map<ComparisonVariant, _ResultState> states;
  final ValueChanged<String> onCopy;

  String get _temperatureLabel => temperature == 0 ? '0' : '$temperature';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE2ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.device_thermostat_rounded,
                  color: Color(0xFF3659D9),
                  size: 21,
                ),
                const SizedBox(width: 8),
                Text(
                  'Temperature: $_temperatureLabel',
                  key: Key('temperature-$_temperatureLabel'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          for (var index = 0; index < variants.length; index++) ...[
            _AnswerCard(
              variant: variants[index],
              state: states[variants[index]]!,
              onCopy: onCopy,
            ),
            if (index != variants.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.variant,
    required this.state,
    required this.onCopy,
  });

  final ComparisonVariant variant;
  final _ResultState state;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final title = 'Вариант ${variant.variantNumber}';
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE1E6EF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading)
            const LinearProgressIndicator(minHeight: 3)
          else
            const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF344054),
                    ),
                  ),
                ),
                if (state.value != null)
                  IconButton(
                    onPressed: () => onCopy(state.value!),
                    tooltip: 'Копировать $title',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE9EDF4)),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 158, maxHeight: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                liveRegion: true,
                label: state.loading ? '$title загружается' : title,
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (state.error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB42318),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              state.error!,
              style: const TextStyle(color: Color(0xFF912018), height: 1.4),
            ),
          ),
        ],
      );
    }
    if (state.value != null) {
      return SelectableText(
        state.value!,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          color: Color(0xFF253047),
        ),
      );
    }
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text(
                'Формируем ответ…',
                style: TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 46),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_rounded, color: Color(0xFFABB4C5), size: 28),
            SizedBox(height: 10),
            Text(
              'Здесь появится ответ',
              style: TextStyle(color: Color(0xFF7A8496)),
            ),
          ],
        ),
      ),
    );
  }
}
