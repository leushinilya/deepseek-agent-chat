import 'package:deepseek_agent_chat/agents/models.dart';
import 'package:deepseek_agent_chat/agents/repository.dart';
import 'package:deepseek_agent_chat/pages/projects_page.dart';
import 'package:deepseek_agent_chat/pages/tasks_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AgentChatRepository repository;
  late AiAgent agent;
  late AgentProject project;
  late AgentTask task;

  setUp(() async {
    repository = AgentChatRepository(_Store());
    await repository.load();
    agent = repository.createAgent(
      name: 'Помощник',
      systemPrompt: 'Помогай',
      model: AgentModel.localGigaChat,
    );
    project = repository.createProject(title: 'Мобильное приложение');
    task = repository.createTask(projectId: project.id, title: 'Экран входа');
    repository.createChat(agentId: agent.id, taskId: task.id);
  });

  testWidgets('tasks page adds and deletes working memory', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    await tester.tap(find.byKey(Key('addWorkingMemory-${task.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('taskMemoryField')), 'Сделать экран входа');
    await tester.tap(find.byKey(const Key('saveTaskMemoryButton')));
    await tester.pumpAndSettle();

    final item = repository.workingMemory(task.id).items.single;
    expect(find.text('Сделать экран входа'), findsOneWidget);
    await tester.tap(find.byKey(Key('deleteWorkingMemory-${item.id}')));
    await tester.pump();
    expect(repository.workingMemory(task.id).items, isEmpty);
  });

  testWidgets('new task requires and stores selected project', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));
    await tester.tap(find.byKey(const Key('createTaskButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('taskProjectField')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('taskTitleField')), 'Новая задача');
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    final created =
        repository.tasks.firstWhere((item) => item.title == 'Новая задача');
    expect(created.projectId, project.id);
  });

  testWidgets('project adds and deletes long-term memory', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ProjectsPage(repository: repository)));

    await tester.tap(find.byKey(Key('addLongTermMemory-${project.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('projectMemoryField')),
        'Пользователь предпочитает Flutter');
    await tester.tap(find.byKey(const Key('saveProjectMemoryButton')));
    await tester.pumpAndSettle();

    final item = repository.longTermMemory(project.id).items.single;
    expect(find.text('Пользователь предпочитает Flutter'), findsOneWidget);
    await tester.tap(find.byKey(Key('deleteLongTermMemory-${item.id}')));
    await tester.pump();
    expect(repository.longTermMemory(project.id).items, isEmpty);
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
