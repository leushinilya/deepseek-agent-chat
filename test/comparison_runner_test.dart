import 'dart:async';

import 'package:deepseek_agent_chat/comparison/comparison_api.dart';
import 'package:deepseek_agent_chat/comparison/comparison_runner.dart';
import 'package:deepseek_agent_chat/comparison/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts all nine variants and evaluates the complete result', () async {
    final gateway = _FakeGateway();
    final updates = <VariantUpdate>[];
    final evaluations = <EvaluationUpdate>[];
    final runner = ComparisonRunner(() => gateway);

    final running = runner.run(
      query: 'query',
      onUpdate: updates.add,
      onEvaluation: evaluations.add,
    );

    expect(gateway.calls, hasLength(9));
    expect(gateway.calls.where((value) => value == 0), hasLength(3));
    expect(gateway.calls.where((value) => value == 0.7), hasLength(3));
    expect(gateway.calls.where((value) => value == 1.2), hasLength(3));
    expect(updates, isEmpty);

    gateway.completeSuccessfully();
    await running;
    expect(updates.map((item) => item.variant).toSet(),
        ComparisonVariant.values.toSet());
    expect(evaluations.single.value, isNotNull);
    expect(gateway.evaluatedAnswers, hasLength(9));
  });

  test('one failed variant does not suppress successful results', () async {
    final gateway = _FakeGateway();
    final updates = <VariantUpdate>[];
    final evaluations = <EvaluationUpdate>[];
    final runner = ComparisonRunner(() => gateway);
    final running = runner.run(
      query: 'query',
      onUpdate: updates.add,
      onEvaluation: evaluations.add,
    );

    gateway.completers.first
        .completeError(const ComparisonApiException('variant failed'));
    gateway.completeSuccessfully();
    await running;

    expect(
        updates.where((item) => item.error == 'variant failed'), hasLength(1));
    expect(updates.where((item) => item.value != null), hasLength(8));
    expect(evaluations.single.error, contains('не все ответы'));
  });

  test('a new run closes the old gateway and ignores stale results', () async {
    final first = _FakeGateway();
    final second = _FakeGateway();
    var factoryCall = 0;
    final updates = <VariantUpdate>[];
    final runner = ComparisonRunner(() => factoryCall++ == 0 ? first : second);

    final firstRun = runner.run(
      query: 'old',
      onUpdate: updates.add,
      onEvaluation: (_) {},
    );
    final secondRun = runner.run(
      query: 'new',
      onUpdate: updates.add,
      onEvaluation: (_) {},
    );
    expect(first.closed, isTrue);
    first.completeSuccessfully(prefix: 'old');
    second.completeSuccessfully(prefix: 'new');
    await Future.wait([firstRun, secondRun]);

    expect(updates, hasLength(9));
    expect(updates.where((item) => item.value!.contains('old')), isEmpty);
  });
}

class _FakeGateway implements ComparisonGateway {
  final completers = <Completer<String>>[];
  final calls = <double>[];
  Map<ComparisonVariant, String>? evaluatedAnswers;
  bool closed = false;

  @override
  Future<String> fetchAnswer(String query, double temperature) {
    calls.add(temperature);
    final completer = Completer<String>();
    completers.add(completer);
    return completer.future;
  }

  @override
  Future<ComparisonEvaluation> evaluate(
    String query,
    Map<ComparisonVariant, String> answers,
  ) async {
    evaluatedAnswers = Map.of(answers);
    return const ComparisonEvaluation(items: [
      TemperatureEvaluation(
        temperature: 0,
        accuracy: 9,
        creativity: 4,
        diversity: 3,
        summary: 'stable',
      ),
      TemperatureEvaluation(
        temperature: 0.7,
        accuracy: 8,
        creativity: 7,
        diversity: 7,
        summary: 'balanced',
      ),
      TemperatureEvaluation(
        temperature: 1.2,
        accuracy: 6,
        creativity: 9,
        diversity: 9,
        summary: 'creative',
      ),
    ]);
  }

  void completeSuccessfully({String prefix = 'result'}) {
    for (var index = 0; index < completers.length; index++) {
      if (!completers[index].isCompleted) {
        completers[index].complete('$prefix ${calls[index]} #${index + 1}');
      }
    }
  }

  @override
  void close() => closed = true;
}
