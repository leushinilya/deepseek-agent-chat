import 'comparison_api.dart';
import 'models.dart';

typedef GatewayFactory = ComparisonGateway Function();
typedef UpdateCallback = void Function(ModelUpdate update);

class ComparisonRunner {
  ComparisonRunner(this._gatewayFactory);

  final GatewayFactory _gatewayFactory;
  ComparisonGateway? _activeGateway;
  int _generation = 0;

  Future<void> run({
    required String query,
    required Iterable<ModelTarget> targets,
    required UpdateCallback onUpdate,
  }) async {
    cancel();
    final generation = _generation;
    final gateway = _gatewayFactory();
    _activeGateway = gateway;
    await Future.wait([
      for (final target in targets)
        _capture(
            target, gateway.fetchAnswer(query, target), generation, onUpdate),
    ]);
    if (generation == _generation) {
      gateway.close();
      _activeGateway = null;
    }
  }

  Future<void> _capture(ModelTarget target, Future<ModelResponse> operation,
      int generation, UpdateCallback onUpdate) async {
    try {
      final value = await operation;
      if (generation == _generation) {
        onUpdate(ModelUpdate(target: target, value: value));
      }
    } catch (error) {
      if (generation == _generation) {
        final message = error is ComparisonApiException
            ? error.message
            : 'Не удалось получить этот ответ.';
        onUpdate(ModelUpdate(target: target, error: message));
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
