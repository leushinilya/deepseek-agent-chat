enum ComparisonScenario { direct, explained, prompted, roles }

class ExplainedResult {
  const ExplainedResult({required this.answer, required this.reasoningSummary});
  final String answer;
  final String reasoningSummary;
}

class PromptedResult {
  const PromptedResult({required this.generatedPrompt, required this.answer});
  final String generatedPrompt;
  final String answer;
}

class RoleAnswer {
  const RoleAnswer({required this.role, required this.answer});
  final String role;
  final String answer;
}

class ScenarioUpdate {
  const ScenarioUpdate({required this.scenario, this.value, this.error});
  final ComparisonScenario scenario;
  final Object? value;
  final String? error;
}
