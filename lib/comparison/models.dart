enum ComparisonVariant {
  temperature0Variant1(0, 1),
  temperature0Variant2(0, 2),
  temperature0Variant3(0, 3),
  temperature07Variant1(0.7, 1),
  temperature07Variant2(0.7, 2),
  temperature07Variant3(0.7, 3),
  temperature12Variant1(1.2, 1),
  temperature12Variant2(1.2, 2),
  temperature12Variant3(1.2, 3);

  const ComparisonVariant(this.temperature, this.variantNumber);

  final double temperature;
  final int variantNumber;
}

class VariantUpdate {
  const VariantUpdate({required this.variant, this.value, this.error});

  final ComparisonVariant variant;
  final String? value;
  final String? error;
}

class TemperatureEvaluation {
  const TemperatureEvaluation({
    required this.temperature,
    required this.accuracy,
    required this.creativity,
    required this.diversity,
    required this.summary,
  });

  final double temperature;
  final int accuracy;
  final int creativity;
  final int diversity;
  final String summary;
}

class ComparisonEvaluation {
  const ComparisonEvaluation({required this.items});

  final List<TemperatureEvaluation> items;
}

class EvaluationUpdate {
  const EvaluationUpdate({this.value, this.error});

  final ComparisonEvaluation? value;
  final String? error;
}
