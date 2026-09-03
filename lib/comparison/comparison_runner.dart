import 'comparison_api.dart';
import 'models.dart';

typedef GatewayFactory = ComparisonGateway Function();
typedef UpdateCallback = void Function(VariantUpdate update);
typedef EvaluationCallback = void Function(EvaluationUpdate update);

class ComparisonRunner {
  ComparisonRunner(this._gatewayFactory);

  final GatewayFactory _gatewayFactory;
  ComparisonGateway? _activeGateway;
  int _generation = 0;

  Future<void> run({
    required String query,
    required UpdateCallback onUpdate,
    required EvaluationCallback onEvaluation,
  }) async {
    cancel();
    final generation = _generation;
    final gateway = _gatewayFactory();
    _activeGateway = gateway;

    final answers = <ComparisonVariant, String>{};
    await Future.wait([
      for (final variant in ComparisonVariant.values)
        _capture(
          variant,
          gateway.fetchAnswer(query, variant.temperature),
          generation,
          onUpdate,
          answers,
        ),
    ]);

    if (generation == _generation) {
      if (answers.length != ComparisonVariant.values.length) {
        onEvaluation(const EvaluationUpdate(
          error: 'Итоговая оценка недоступна: получены не все ответы.',
        ));
      } else {
        try {
          final evaluation = await gateway.evaluate(query, answers);
          if (generation == _generation) {
            onEvaluation(EvaluationUpdate(value: evaluation));
          }
        } catch (error) {
          if (generation == _generation) {
            final message = error is ComparisonApiException
                ? error.message
                : 'Не удалось получить итоговую оценку.';
            onEvaluation(EvaluationUpdate(error: message));
          }
        }
      }
    }

    if (generation == _generation) {
      gateway.close();
      _activeGateway = null;
    }
  }

  Future<void> _capture(
    ComparisonVariant variant,
    Future<String> operation,
    int generation,
    UpdateCallback onUpdate,
    Map<ComparisonVariant, String> answers,
  ) async {
    try {
      final value = await operation;
      if (generation == _generation) {
        answers[variant] = value;
        onUpdate(VariantUpdate(variant: variant, value: value));
      }
    } catch (error) {
      if (generation == _generation) {
        final message = error is ComparisonApiException
            ? error.message
            : 'Не удалось получить этот ответ.';
        onUpdate(VariantUpdate(variant: variant, error: message));
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
