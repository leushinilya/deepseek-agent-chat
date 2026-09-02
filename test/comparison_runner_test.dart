import 'dart:async';

import 'package:deepseek_agent_chat/comparison/comparison_api.dart';
import 'package:deepseek_agent_chat/comparison/comparison_runner.dart';
import 'package:deepseek_agent_chat/comparison/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts all four scenarios before any result completes', () async {
    final gateway = _FakeGateway();
    final updates = <ScenarioUpdate>[];
    final runner = ComparisonRunner(() => gateway);

    final running = runner.run(
        query: 'query', roles: const ['role'], onUpdate: updates.add);
    expect(gateway.started, ComparisonScenario.values.toSet());
    expect(updates, isEmpty);

    gateway.completeSuccessfully();
    await running;
    expect(updates.map((item) => item.scenario).toSet(),
        ComparisonScenario.values.toSet());
  });

  test('one failed scenario does not suppress successful results', () async {
    final gateway = _FakeGateway();
    final updates = <ScenarioUpdate>[];
    final runner = ComparisonRunner(() => gateway);
    final running = runner.run(
        query: 'query', roles: const ['role'], onUpdate: updates.add);

    gateway.direct.completeError(const ComparisonApiException('direct failed'));
    gateway.explained.complete(
        const ExplainedResult(answer: 'answer', reasoningSummary: 'summary'));
    gateway.prompted.complete(
        const PromptedResult(generatedPrompt: 'prompt', answer: 'answer'));
    gateway.roles.complete(const [RoleAnswer(role: 'role', answer: 'answer')]);
    await running;

    expect(
        updates
            .singleWhere((item) => item.scenario == ComparisonScenario.direct)
            .error,
        'direct failed');
    expect(updates.where((item) => item.value != null), hasLength(3));
  });

  test('a new run closes the old gateway and ignores its stale results',
      () async {
    final first = _FakeGateway();
    final second = _FakeGateway();
    var factoryCall = 0;
    final updates = <ScenarioUpdate>[];
    final runner = ComparisonRunner(() => factoryCall++ == 0 ? first : second);

    final firstRun =
        runner.run(query: 'old', roles: const ['role'], onUpdate: updates.add);
    final secondRun =
        runner.run(query: 'new', roles: const ['role'], onUpdate: updates.add);
    expect(first.closed, isTrue);
    first.completeSuccessfully(prefix: 'old');
    second.completeSuccessfully(prefix: 'new');
    await Future.wait([firstRun, secondRun]);

    expect(updates, hasLength(4));
    expect(updates.where((item) => item.value.toString().contains('old')),
        isEmpty);
  });
}

class _FakeGateway implements ComparisonGateway {
  final direct = Completer<String>();
  final explained = Completer<ExplainedResult>();
  final prompted = Completer<PromptedResult>();
  final roles = Completer<List<RoleAnswer>>();
  final started = <ComparisonScenario>{};
  bool closed = false;

  @override
  Future<String> fetchDirect(String query) {
    started.add(ComparisonScenario.direct);
    return direct.future;
  }

  @override
  Future<ExplainedResult> fetchExplained(String query) {
    started.add(ComparisonScenario.explained);
    return explained.future;
  }

  @override
  Future<PromptedResult> fetchPrompted(String query) {
    started.add(ComparisonScenario.prompted);
    return prompted.future;
  }

  @override
  Future<List<RoleAnswer>> fetchRoles(String query, List<String> roleList) {
    started.add(ComparisonScenario.roles);
    return roles.future;
  }

  void completeSuccessfully({String prefix = 'result'}) {
    if (!direct.isCompleted) {
      direct.complete('$prefix direct');
    }
    if (!explained.isCompleted) {
      explained.complete(ExplainedResult(
          answer: '$prefix answer', reasoningSummary: '$prefix summary'));
    }
    if (!prompted.isCompleted) {
      prompted.complete(PromptedResult(
          generatedPrompt: '$prefix prompt', answer: '$prefix answer'));
    }
    if (!roles.isCompleted) {
      roles.complete([RoleAnswer(role: 'role', answer: '$prefix role answer')]);
    }
  }

  @override
  void close() => closed = true;
}
