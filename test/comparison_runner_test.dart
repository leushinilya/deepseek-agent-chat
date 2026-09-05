import 'dart:async';

import 'package:deepseek_agent_chat/comparison/comparison_api.dart';
import 'package:deepseek_agent_chat/comparison/comparison_runner.dart';
import 'package:deepseek_agent_chat/comparison/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts all three models in parallel', () async {
    final gateway = _FakeGateway();
    final updates = <ModelUpdate>[];
    final runner = ComparisonRunner(() => gateway);
    final running = runner.run(
        query: 'query', targets: ModelTarget.values, onUpdate: updates.add);

    expect(gateway.calls, ModelTarget.values);
    expect(updates, isEmpty);
    gateway.completeSuccessfully();
    await running;

    expect(
        updates.map((item) => item.target).toSet(), ModelTarget.values.toSet());
    expect(updates.every((item) => item.value != null), isTrue);
  });

  test('one failed model does not suppress successful results', () async {
    final gateway = _FakeGateway();
    final updates = <ModelUpdate>[];
    final runner = ComparisonRunner(() => gateway);
    final running = runner.run(
        query: 'query', targets: ModelTarget.values, onUpdate: updates.add);

    gateway.completers.first
        .completeError(const ComparisonApiException('model failed'));
    gateway.completeSuccessfully();
    await running;

    expect(updates.where((item) => item.error == 'model failed'), hasLength(1));
    expect(updates.where((item) => item.value != null), hasLength(2));
  });

  test('a new run closes the old gateway and ignores stale results', () async {
    final first = _FakeGateway();
    final second = _FakeGateway();
    var factoryCall = 0;
    final updates = <ModelUpdate>[];
    final runner = ComparisonRunner(() => factoryCall++ == 0 ? first : second);

    final firstRun = runner.run(
        query: 'old', targets: ModelTarget.values, onUpdate: updates.add);
    final secondRun = runner.run(
        query: 'new', targets: ModelTarget.values, onUpdate: updates.add);
    expect(first.closed, isTrue);
    first.completeSuccessfully(prefix: 'old');
    second.completeSuccessfully(prefix: 'new');
    await Future.wait([firstRun, secondRun]);

    expect(updates, hasLength(3));
    expect(
        updates.where((item) => item.value!.answer.contains('old')), isEmpty);
  });

  test('starts only selected models', () async {
    final gateway = _FakeGateway();
    final runner = ComparisonRunner(() => gateway);
    final running = runner.run(
      query: 'query',
      targets: [ModelTarget.gigaChat, ModelTarget.deepseekFlash],
      onUpdate: (_) {},
    );

    expect(gateway.calls, [ModelTarget.gigaChat, ModelTarget.deepseekFlash]);
    gateway.completeSuccessfully();
    await running;
  });
}

class _FakeGateway implements ComparisonGateway {
  final completers = <Completer<ModelResponse>>[];
  final calls = <ModelTarget>[];
  bool closed = false;

  @override
  Future<ModelResponse> fetchAnswer(String query, ModelTarget target) {
    calls.add(target);
    final completer = Completer<ModelResponse>();
    completers.add(completer);
    return completer.future;
  }

  void completeSuccessfully({String prefix = 'result'}) {
    for (var index = 0; index < completers.length; index++) {
      if (!completers[index].isCompleted) {
        completers[index].complete(ModelResponse(
          answer: '$prefix ${calls[index].id}',
          durationMs: 1200,
          promptTokens: 10,
          completionTokens: 20,
          totalTokens: 30,
          costUsd: calls[index].isPaid ? 0.0001 : null,
        ));
      }
    }
  }

  @override
  void close() => closed = true;
}
