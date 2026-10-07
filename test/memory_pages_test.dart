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

  testWidgets('tasks page edits unified working memory', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    await tester.tap(find.byKey(Key('editWorkingMemory-${task.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('taskMemoryField')), 'Сделать экран входа');
    await tester.tap(find.byKey(const Key('saveTaskMemoryButton')));
    await tester.pumpAndSettle();

    expect(find.text('Рабочая память'), findsOneWidget);
    expect(find.text('Сделать экран входа'), findsOneWidget);
    await tester.tap(find.byKey(Key('editWorkingMemory-${task.id}')));
    await tester.pumpAndSettle();
    final memoryField =
        tester.widget<TextField>(find.byKey(const Key('taskMemoryField')));
    expect(memoryField.controller!.text, 'Сделать экран входа');
    await tester.enterText(find.byKey(const Key('taskMemoryField')), '');
    await tester.tap(find.byKey(const Key('saveTaskMemoryButton')));
    await tester.pumpAndSettle();
    expect(repository.workingMemory(task.id).content, isEmpty);
  });

  testWidgets('new task requires and stores selected project', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));
    await tester.tap(find.byKey(const Key('createTaskButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('taskProjectField')), findsOneWidget);
    expect(find.byKey(const Key('taskAgentField')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('taskTitleField')), 'Новая задача');
    await tester.tap(find.byKey(const Key('saveTaskButton')));
    await tester.pumpAndSettle();

    final created =
        repository.tasks.firstWhere((item) => item.title == 'Новая задача');
    expect(created.projectId, project.id);
    expect(created.agentId, agent.id);
  });

  testWidgets('task button opens chats filtered by task', (tester) async {
    final otherTask =
        repository.createTask(projectId: project.id, title: 'Другая задача');
    final ownChat = repository.chats.single;
    repository.appendMessage(ownChat.id, ChatRole.user, 'Чат экрана входа');
    final otherChat =
        repository.createChat(agentId: agent.id, taskId: otherTask.id);
    repository.appendMessage(otherChat.id, ChatRole.user, 'Чужой чат');
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    final chatsButton = find.byKey(Key('taskChats-${task.id}'));
    await tester.scrollUntilVisible(chatsButton, 300);
    await tester.pumpAndSettle();
    await tester.tap(chatsButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Чаты · Экран входа'), findsOneWidget);
    expect(find.text('Чат экрана входа'), findsOneWidget);
    expect(find.text('Чужой чат'), findsNothing);
  });

  testWidgets('task deletion warns and cascades linked chats', (tester) async {
    final chatId = repository.chats.single.id;
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    await tester.tap(find.byKey(Key('deleteTask-${task.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Все вложенные чаты (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelDeleteTaskButton')));
    await tester.pumpAndSettle();
    expect(repository.taskById(task.id), isNotNull);
    expect(repository.chatById(chatId), isNotNull);

    await tester.tap(find.byKey(Key('deleteTask-${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteTaskButton')));
    await tester.pumpAndSettle();
    expect(repository.taskById(task.id), isNull);
    expect(repository.chatById(chatId), isNull);
  });

  testWidgets('task card does not contain state transition buttons',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    expect(find.byKey(Key('advanceTaskState-${task.id}')), findsNothing);
  });

  testWidgets('task card shows completed stage result', (tester) async {
    final model = repository.createStateModel(title: 'Разработка');
    repository.addStateToModel(model.id,
        name: 'План', description: 'Составить план', colorValue: 0xFF3659D9);
    repository.addStateToModel(model.id,
        name: 'Работа', description: 'Выполнить план', colorValue: 0xFF039855);
    repository.assignStateModelToProject(project.id, model.id);
    repository.completeCurrentTaskState(task.id, 'Результат планирования');
    await tester
        .pumpWidget(MaterialApp(home: TasksPage(repository: repository)));

    expect(find.text('Работа'), findsOneWidget);
    expect(find.text('Выполненные этапы'), findsOneWidget);
    await tester.tap(find.text('План'));
    await tester.pumpAndSettle();
    expect(find.text('Результат планирования'), findsOneWidget);
    final statusY = tester.getTopLeft(find.text('Работа')).dy;
    final memoryY = tester.getTopLeft(find.text('Рабочая память')).dy;
    final stagesY = tester.getTopLeft(find.text('Выполненные этапы')).dy;
    final chatsY = tester
        .getTopLeft(find.widgetWithText(FilledButton, 'Чаты задачи (1)'))
        .dy;
    expect(statusY, lessThan(memoryY));
    expect(memoryY, lessThan(stagesY));
    expect(stagesY, lessThan(chatsY));
  });

  testWidgets('project edits and clears a unified long-term prompt',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ProjectsPage(repository: repository)));

    await tester.tap(find.byKey(Key('editLongTermMemory-${project.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('projectMemoryField')),
        'Пользователь предпочитает Flutter');
    await tester.tap(find.byKey(const Key('saveProjectMemoryButton')));
    await tester.pumpAndSettle();

    expect(repository.longTermMemory(project.id).content,
        'Пользователь предпочитает Flutter');
    expect(find.text('Пользователь предпочитает Flutter'), findsOneWidget);
    await tester.tap(find.byKey(Key('editLongTermMemory-${project.id}')));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('projectMemoryField')));
    expect(field.controller!.text, 'Пользователь предпочитает Flutter');
    await tester.enterText(find.byKey(const Key('projectMemoryField')), '');
    await tester.tap(find.byKey(const Key('saveProjectMemoryButton')));
    await tester.pumpAndSettle();
    expect(repository.longTermMemory(project.id).content, isEmpty);
  });

  testWidgets('project card adds and deletes an invariant', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ProjectsPage(repository: repository)));

    await tester.tap(find.byKey(Key('editInvariants-${project.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('addInvariant-${project.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('invariantNameField')), 'Не публиковать секреты');
    await tester.enterText(find.byKey(const Key('invariantDescriptionField')),
        'Нельзя выводить ключи доступа и пароли.');
    await tester.tap(find.byKey(const Key('saveInvariantButton')));
    await tester.pumpAndSettle();

    final invariant = repository.projectById(project.id)!.invariants.single;
    expect(find.text('Не публиковать секреты'), findsOneWidget);
    expect(
        find.text('Нельзя выводить ключи доступа и пароли.'), findsOneWidget);
    await tester.tap(find.byKey(Key('deleteInvariant-${invariant.id}')));
    await tester.pump();
    expect(repository.projectById(project.id)!.invariants, isEmpty);
  });
}

class _Store implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
