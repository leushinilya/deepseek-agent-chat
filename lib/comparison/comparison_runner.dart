import 'comparison_api.dart';
import 'models.dart';

typedef GatewayFactory = ComparisonGateway Function();
typedef UpdateCallback = void Function(ScenarioUpdate update);

class ComparisonRunner {
  ComparisonRunner(this._gatewayFactory);
  final GatewayFactory _gatewayFactory;
  ComparisonGateway? _activeGateway;
  int _generation = 0;

  Future<void> run(
      {required String query,
      required List<String> roles,
      required UpdateCallback onUpdate}) async {
    cancel();
    final generation = _generation;
    final gateway = _gatewayFactory();
    _activeGateway = gateway;
    await Future.wait(<Future<void>>[
      _capture(ComparisonScenario.direct, gateway.fetchDirect(query),
          generation, onUpdate),
      _capture(ComparisonScenario.explained, gateway.fetchExplained(query),
          generation, onUpdate),
      _capture(ComparisonScenario.prompted, gateway.fetchPrompted(query),
          generation, onUpdate),
      _capture(ComparisonScenario.roles, gateway.fetchRoles(query, roles),
          generation, onUpdate),
    ]);
    if (generation == _generation) {
      gateway.close();
      _activeGateway = null;
    }
  }

  Future<void> _capture(ComparisonScenario scenario, Future<Object?> operation,
      int generation, UpdateCallback onUpdate) async {
    try {
      final value = await operation;
      if (generation == _generation) {
        onUpdate(ScenarioUpdate(scenario: scenario, value: value));
      }
    } catch (error) {
      if (generation == _generation) {
        final message = error is ComparisonApiException
            ? error.message
            : 'Не удалось получить этот ответ.';
        onUpdate(ScenarioUpdate(scenario: scenario, error: message));
      }
    }
  }

  void cancel() {
    _generation += 1;
    _activeGateway?.close();
    _activeGateway = null;
  }

  void dispose() => cancel();
}
