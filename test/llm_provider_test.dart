import 'dart:convert';

import 'package:deepseek_agent_chat/agents/llm_provider.dart';
import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final agent = AiAgent(
    id: 'a',
    name: 'Test',
    systemPrompt: 'System only',
    model: AgentModel.deepseekPro,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  final messages = [
    ChatMessage(
      id: 'm',
      role: ChatRole.user,
      content: 'Hello',
      createdAt: DateTime.utc(2026),
    ),
  ];

  test('forwards provider, exact model, prompt and streams response', () async {
    late Map<String, dynamic> body;
    final provider = BackendLlmProvider(
        clientFactory: () => MockClient.streaming(
              (request, _) async {
                body = jsonDecode((request as http.Request).body)
                    as Map<String, dynamic>;
                return http.StreamedResponse(
                  Stream.fromIterable([
                    utf8.encode('{"type":"delta","text":"Hel"}\n'),
                    utf8.encode('{"type":"delta","text":"lo"}\n'),
                    utf8.encode(
                        '{"type":"done","promptTokens":12,"completionTokens":7}\n'),
                  ]),
                  200,
                );
              },
            ));
    final events = await provider
        .send(LlmRequest(
            agent: agent,
            messages: messages,
            summary: 'Prior summary',
            facts: const {'goal': 'Ship'},
            workingMemory: 'Finish login screen',
            longTermMemory: const ['Prefers Flutter'],
            taskState: const TaskStateDefinition(
              id: 'planning',
              name: 'Planning',
              description: 'Create an implementation plan only',
              colorValue: 0xFF3659D9,
            ),
            taskStateModel: TaskStateModel(
              id: 'workflow',
              title: 'Delivery',
              states: const [
                TaskStateDefinition(
                    id: 'planning',
                    name: 'Planning',
                    description: 'Create an implementation plan only',
                    colorValue: 0),
                TaskStateDefinition(
                    id: 'implementation',
                    name: 'Implementation',
                    description: 'Write the code',
                    colorValue: 0),
              ],
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            taskStageResults: [
              TaskStageResult(
                stateId: 'discovery',
                stateName: 'Discovery',
                result: 'Requirements collected',
                completedAt: DateTime.utc(2026),
              ),
            ],
            invariants: const [
              ProjectInvariant(
                id: 'inv-1',
                name: 'No secrets',
                description: 'Never reveal credentials',
              ),
            ],
            userProfile: const UserProfile(
                name: 'Anna', style: 'Concise', format: 'Bullets')))
        .events
        .toList();

    expect(body['provider'], 'deepseek');
    expect(body['model'], 'deepseek-v4-pro');
    expect(body['systemPrompt'], 'System only');
    expect(body['contextSummary'], 'Prior summary');
    expect(body['contextFacts'], {'goal': 'Ship'});
    expect(body['workingMemory'], 'Finish login screen');
    expect(body['longTermMemory'], ['Prefers Flutter']);
    expect(body['taskState'], {
      'id': 'planning',
      'name': 'Planning',
      'description': 'Create an implementation plan only',
      'modelName': 'Delivery',
      'states': [
        {
          'id': 'planning',
          'name': 'Planning',
          'description': 'Create an implementation plan only'
        },
        {
          'id': 'implementation',
          'name': 'Implementation',
          'description': 'Write the code'
        },
      ],
    });
    expect(body['taskStageResults'], [
      {'stateName': 'Discovery', 'result': 'Requirements collected'}
    ]);
    expect(body['invariants'], [
      {'name': 'No secrets', 'description': 'Never reveal credentials'}
    ]);
    expect(body['userProfile'],
        {'name': 'Anna', 'style': 'Concise', 'format': 'Bullets'});
    expect(events.whereType<LlmTextDelta>().map((event) => event.text),
        ['Hel', 'lo']);
    expect(events.last, isA<LlmDone>());
    expect((events.last as LlmDone).promptTokens, 12);
    expect((events.last as LlmDone).completionTokens, 7);
  });

  test('maps streamed provider error to safe exception', () async {
    final provider = BackendLlmProvider(
        clientFactory: () => MockClient.streaming(
              (_, __) async => http.StreamedResponse(
                Stream.value(utf8.encode(
                    '{"type":"error","message":"Нет API-ключа","code":"missing_api_key"}\n')),
                200,
              ),
            ));
    expect(
      provider
          .send(LlmRequest(agent: agent, messages: messages))
          .events
          .toList(),
      throwsA(isA<LlmException>()
          .having((error) => error.code, 'code', 'missing_api_key')),
    );
  });
}
