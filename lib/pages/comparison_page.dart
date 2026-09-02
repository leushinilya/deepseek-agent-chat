import 'dart:async';

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
  final _rolesController = TextEditingController();
  final _queryFocus = FocusNode();
  late final ComparisonRunner _runner =
      ComparisonRunner(() => ComparisonApiClient());
  final _states = <ComparisonScenario, _ResultState>{
    for (final scenario in ComparisonScenario.values)
      scenario: const _ResultState(),
  };
  String? _queryError;
  String? _rolesError;

  bool get _isRunning => _states.values.any((state) => state.loading);

  @override
  void dispose() {
    _runner.dispose();
    _queryController.dispose();
    _rolesController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _runComparison() async {
    String query;
    List<String> roles;
    setState(() {
      _queryError = null;
      _rolesError = null;
    });
    try {
      query = validateQuery(_queryController.text);
    } on InputValidationException catch (error) {
      setState(() => _queryError = error.message);
      _queryFocus.requestFocus();
      return;
    }
    try {
      roles = parseRoles(_rolesController.text);
    } on InputValidationException catch (error) {
      setState(() => _rolesError = error.message);
      return;
    }

    setState(() {
      for (final scenario in ComparisonScenario.values) {
        _states[scenario] =
            _states[scenario]!.copyWith(loading: true, clearError: true);
      }
    });
    await _runner.run(query: query, roles: roles, onUpdate: _applyUpdate);
  }

  void _applyUpdate(ScenarioUpdate update) {
    if (!mounted) return;
    setState(() {
      _states[update.scenario] = _ResultState(
          value: update.value, error: update.error, loading: false);
    });
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label скопирован'),
        duration: const Duration(seconds: 2)));
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
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildComposer(),
                        const SizedBox(height: 24),
                        _buildResults(),
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
        constraints: const BoxConstraints(maxWidth: 1440),
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
                    Text('AI · четыре подхода',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    const Text(
                        'Один запрос — четыре независимых способа получить ответ',
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final queryField = TextField(
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
          );
          final rolesField = TextField(
            key: const Key('rolesField'),
            controller: _rolesController,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Роли',
              alignLabelWithHint: true,
              hintText: 'учёный, программист, врач',
              helperText: 'Через запятую или с новой строки · до 10 ролей',
              errorText: _rolesError,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: queryField),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: rolesField)
                ])
              else ...[
                queryField,
                const SizedBox(height: 16),
                rolesField,
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: _isRunning
                      ? 'Перезапустить сравнение и отменить текущие запросы'
                      : 'Получить четыре ответа',
                  child: FilledButton.icon(
                    key: const Key('runButton'),
                    onPressed: _runComparison,
                    icon: Icon(_isRunning
                        ? Icons.refresh_rounded
                        : Icons.auto_awesome_rounded),
                    label: Text(
                        _isRunning ? 'Запустить заново' : 'Получить ответы'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResults() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100 ? 2 : 1;
        const gap = 18.0;
        final width = columns == 2
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        final cards = <Widget>[
          _ResultCard(
            title: 'Обычный ответ',
            subtitle: 'Прямой ответ модели без дополнительных инструкций',
            icon: Icons.chat_bubble_outline_rounded,
            state: _states[ComparisonScenario.direct]!,
            childBuilder: (value) => _TextResult(
                text: value as String, onCopy: () => _copy(value, 'Ответ')),
          ),
          _ResultCard(
            title: 'Ответ с объяснением',
            subtitle:
                'Ответ и краткое резюме оснований — без скрытой цепочки рассуждений',
            icon: Icons.lightbulb_outline_rounded,
            state: _states[ComparisonScenario.explained]!,
            childBuilder: (value) {
              final result = value as ExplainedResult;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                        label: 'Итоговый ответ',
                        text: result.answer,
                        onCopy: () => _copy(result.answer, 'Ответ')),
                    const SizedBox(height: 18),
                    _Section(
                        label: 'Ключевые шаги и допущения',
                        text: result.reasoningSummary,
                        onCopy: () =>
                            _copy(result.reasoningSummary, 'Объяснение')),
                  ]);
            },
          ),
          _ResultCard(
            title: 'Ответ через улучшенный промт',
            subtitle:
                'Сначала запрос уточняется, затем модель отвечает на улучшенную версию',
            icon: Icons.tune_rounded,
            state: _states[ComparisonScenario.prompted]!,
            childBuilder: (value) {
              final result = value as PromptedResult;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                        label: 'Сгенерированный промт',
                        text: result.generatedPrompt,
                        tinted: true,
                        onCopy: () => _copy(result.generatedPrompt, 'Промт')),
                    const SizedBox(height: 18),
                    _Section(
                        label: 'Итоговый ответ',
                        text: result.answer,
                        onCopy: () => _copy(result.answer, 'Ответ')),
                  ]);
            },
          ),
          _ResultCard(
            title: 'Ответы по ролям',
            subtitle:
                'Несколько взглядов на исходный запрос в отдельных блоках',
            icon: Icons.groups_2_outlined,
            state: _states[ComparisonScenario.roles]!,
            childBuilder: (value) {
              final answers = value as List<RoleAnswer>;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < answers.length; index++) ...[
                    _Section(
                      label: '«${answers[index].role}»',
                      text: answers[index].answer,
                      onCopy: () => _copy(answers[index].answer, 'Ответ роли'),
                    ),
                    if (index != answers.length - 1) const SizedBox(height: 14),
                  ],
                ],
              );
            },
          ),
        ];
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final card in cards) SizedBox(width: width, child: card)
        ]);
      },
    );
  }
}

class _ResultState {
  const _ResultState({this.value, this.error, this.loading = false});
  final Object? value;
  final String? error;
  final bool loading;

  _ResultState copyWith({bool? loading, bool clearError = false}) =>
      _ResultState(
          value: value,
          error: clearError ? null : error,
          loading: loading ?? this.loading);
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.state,
      required this.childBuilder});
  final String title;
  final String subtitle;
  final IconData icon;
  final _ResultState state;
  final Widget Function(Object value) childBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E6EF))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading)
            const LinearProgressIndicator(minHeight: 3)
          else
            const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: const Color(0xFF3659D9), size: 21)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Color(0xFF667085))),
                  ])),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFE9EDF4)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500, minHeight: 205),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Semantics(
                liveRegion: true,
                label: state.loading ? '$title загружается' : title,
                child: _body(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (state.error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFB42318), size: 20),
          const SizedBox(width: 9),
          Expanded(
              child: Text(state.error!,
                  style:
                      const TextStyle(color: Color(0xFF912018), height: 1.4))),
        ]),
      );
    }
    if (state.value != null) return childBuilder(state.value!);
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(height: 12),
          Text('Формируем ответ…', style: TextStyle(color: Color(0xFF667085))),
        ])),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 50),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notes_rounded, color: Color(0xFFABB4C5), size: 30),
        SizedBox(height: 10),
        Text('Здесь появится результат',
            style: TextStyle(color: Color(0xFF7A8496))),
      ])),
    );
  }
}

class _TextResult extends StatelessWidget {
  const _TextResult({required this.text, required this.onCopy});
  final String text;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) =>
      _Section(label: 'Ответ', text: text, onCopy: onCopy);
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.label,
      required this.text,
      required this.onCopy,
      this.tinted = false});
  final String label;
  final String text;
  final VoidCallback onCopy;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: tinted ? const Color(0xFFF4F6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  tinted ? const Color(0xFFDDE3FF) : const Color(0xFFE8ECF2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF344054)))),
          IconButton(
              onPressed: onCopy,
              tooltip: 'Копировать: $label',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18)),
        ]),
        const SizedBox(height: 6),
        SelectableText(text,
            style: const TextStyle(
                fontSize: 15, height: 1.55, color: Color(0xFF253047))),
      ]),
    );
  }
}
