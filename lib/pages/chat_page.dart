import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agents/llm_provider.dart';
import '../agents/context_compressor.dart';
import '../agents/facts_updater.dart';
import '../agents/models.dart';
import '../agents/repository.dart';
import '../agents/token_counter.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.repository,
    required this.chatId,
    required this.provider,
    super.key,
  });

  final AgentChatRepository repository;
  final String chatId;
  final LlmProvider provider;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  LlmOperation? _operation;
  StreamSubscription<LlmEvent>? _subscription;
  String _streamingText = '';
  String? _error;
  bool _generating = false;
  bool _finalized = false;
  int? _completionTokens;
  ContextCompressor? _compressor;
  FactsUpdater? _factsUpdater;
  bool _compressing = false;
  bool get _isGenerating =>
      _generating || widget.repository.isChatScheduleGenerating(widget.chatId);
  int? _expandedSummaryCount;
  int? _expandedWindowCount;
  final _compressionForm = GlobalKey<FormState>();
  late final TextEditingController _maxController;
  late final TextEditingController _minController;
  late final TextEditingController _windowController;

  @override
  void initState() {
    super.initState();
    final chat = widget.repository.chatById(widget.chatId);
    _maxController =
        TextEditingController(text: '${chat?.compressionMax ?? 20}');
    _minController =
        TextEditingController(text: '${chat?.compressionMin ?? 6}');
    _windowController =
        TextEditingController(text: '${chat?.windowSize ?? 12}');
  }

  @override
  void dispose() {
    _maxController.dispose();
    _minController.dispose();
    _windowController.dispose();
    _compressor?.cancel();
    _factsUpdater?.cancel();
    _operation?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send({bool addUserMessage = true}) async {
    if (_isGenerating) return;
    final chat = widget.repository.chatById(widget.chatId);
    if (chat == null) return;
    if (!(_compressionForm.currentState?.validate() ?? true)) return;
    final task = widget.repository.taskById(chat.taskId);
    final agent = widget.repository.agentById(task?.agentId ?? chat.agentId);
    final project =
        task == null ? null : widget.repository.projectById(task.projectId);
    if (task == null || agent == null || project == null) {
      setState(
          () => _error = 'Проект, задача или агент этого чата недоступны.');
      return;
    }
    if (addUserMessage) {
      final text = _controller.text.trim();
      if (text.isEmpty) return;
      widget.repository.appendMessage(widget.chatId, ChatRole.user, text);
      _controller.clear();
    }
    final updatedChat = widget.repository.chatById(widget.chatId)!;
    if (updatedChat.messages.isEmpty ||
        updatedChat.messages.last.role != ChatRole.user) {
      return;
    }
    setState(() {
      _generating = true;
      _streamingText = '';
      _error = null;
      _finalized = false;
      _completionTokens = null;
    });
    _scrollToEnd();
    if (updatedChat.compressionEnabled &&
        updatedChat.contextMessages.length >= updatedChat.compressionMax) {
      setState(() => _compressing = true);
      final compressor = ContextCompressor(widget.repository, widget.provider);
      _compressor = compressor;
      try {
        await compressor.compress(updatedChat, agent);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _generating = false;
          _error = 'Не удалось сжать контекст. История сохранена. '
              '${error is LlmException ? error.message : 'Попробуйте ещё раз.'}';
        });
        return;
      } finally {
        _compressor = null;
        if (mounted) setState(() => _compressing = false);
      }
      if (!mounted) return;
    }
    if (!updatedChat.isPeriodic &&
        updatedChat.contextStrategy == ContextStrategy.stickyFacts) {
      setState(() => _compressing = true);
      final updater = FactsUpdater(widget.repository, widget.provider);
      _factsUpdater = updater;
      try {
        await updater.update(updatedChat, agent);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _generating = false;
          _error = 'Не удалось обновить facts. История сохранена. '
              '${error is LlmException ? error.message : 'Попробуйте ещё раз.'}';
        });
        return;
      } finally {
        _factsUpdater = null;
        if (mounted) setState(() => _compressing = false);
      }
      if (!mounted) return;
    }
    final contextChat = widget.repository.chatById(widget.chatId);
    if (contextChat == null || !mounted) return;
    final working = widget.repository.workingMemory(task.id);
    final longTerm = widget.repository.longTermMemory(project.id);
    final operation = widget.provider.send(
      LlmRequest(
          agent: agent,
          messages: contextChat.contextMessages,
          temperature: contextChat.temperature,
          maxTokens: contextChat.maxTokens,
          contextWindow: contextChat.contextWindow,
          summary: contextChat.contextStrategy == ContextStrategy.compression
              ? contextChat.contextSummary
              : '',
          facts: contextChat.contextStrategy == ContextStrategy.stickyFacts
              ? contextChat.facts
              : const {},
          workingMemory: working.content,
          longTermMemory: longTerm.promptMessages,
          userProfile: widget.repository.userProfile,
          taskState: widget.repository.currentStateForTask(task),
          taskStateModel: widget.repository.stateModelForTask(task),
          taskStageResults: task.stageResults,
          invariants: project.invariants),
    );
    _operation = operation;
    _subscription = operation.events.listen(
      (event) {
        if (!mounted) return;
        if (event is LlmTextDelta) {
          setState(() => _streamingText += event.text);
          _scrollToEnd();
        } else if (event is LlmRagSearch) {
          widget.repository.updateMessageRagSearch(
              widget.chatId, updatedChat.messages.last.id, event.metadata);
        } else if (event is LlmDone) {
          _completionTokens = event.completionTokens;
          _finish();
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _generating = false;
          _error = error is LlmException
              ? error.message
              : 'Не удалось получить ответ. Попробуйте ещё раз.';
        });
      },
      onDone: () {
        if (mounted && _generating) _finish();
      },
    );
  }

  void _finish() {
    if (_finalized) return;
    _finalized = true;
    final answer = _streamingText.trim();
    if (answer.isNotEmpty) {
      widget.repository.appendMessage(
        widget.chatId,
        ChatRole.assistant,
        answer,
        tokenCount: _completionTokens,
      );
    }
    if (mounted) {
      setState(() {
        _generating = false;
        _streamingText = '';
      });
      _scrollToEnd();
    }
  }

  void _stop() {
    if (widget.repository.isChatScheduleGenerating(widget.chatId)) {
      widget.repository.stopChatSchedule(widget.chatId);
      return;
    }
    if (_compressing) {
      _compressor?.cancel();
      _factsUpdater?.cancel();
      return;
    }
    _operation?.cancel();
    _subscription?.cancel();
    _finish();
  }

  Future<void> _refreshFacts({bool rebuild = true}) async {
    if (_generating) return;
    final chat = widget.repository.chatById(widget.chatId);
    final task = chat == null ? null : widget.repository.taskById(chat.taskId);
    final agent = chat == null
        ? null
        : widget.repository.agentById(task?.agentId ?? chat.agentId);
    if (chat == null || agent == null) return;
    if (!chat.messages.any((message) => message.role == ChatRole.user)) return;
    setState(() {
      _generating = true;
      _compressing = true;
      _error = null;
    });
    _scrollToEnd();
    final updater = FactsUpdater(widget.repository, widget.provider);
    _factsUpdater = updater;
    try {
      await updater.update(chat, agent, rebuild: rebuild);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is LlmException
            ? error.message
            : 'Не удалось обновить facts.');
      }
    } finally {
      _factsUpdater = null;
      if (mounted) {
        setState(() {
          _generating = false;
          _compressing = false;
        });
      }
    }
  }

  Future<void> _selectContextStrategy(
      AgentChat chat, ContextStrategy strategy) async {
    widget.repository.updateContextStrategy(chat.id, strategy);
    if (strategy == ContextStrategy.stickyFacts &&
        chat.facts.isEmpty &&
        chat.messages.any((message) => message.role == ChatRole.user)) {
      await _refreshFacts();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.repository,
        builder: (context, _) {
          final chat = widget.repository.chatById(widget.chatId);
          final task =
              chat == null ? null : widget.repository.taskById(chat.taskId);
          final agent = chat == null
              ? null
              : widget.repository.agentById(task?.agentId ?? chat.agentId);
          final project = task == null
              ? null
              : widget.repository.projectById(task.projectId);
          final taskState =
              task == null ? null : widget.repository.currentStateForTask(task);
          if (chat == null ||
              task == null ||
              agent == null ||
              project == null) {
            return const Scaffold(
              body: Center(
                  child: Text('Проект, чат, задача или агент недоступны.')),
            );
          }
          final totalTokens = chat.messages.isEmpty
              ? 0
              : estimateTokenCount(agent.systemPrompt) +
                  estimateTokenCount(chat.activeSummary) +
                  estimateTokenCount(
                      widget.repository.workingMemory(chat.taskId).content) +
                  estimateTokenCount(
                      widget.repository.longTermMemory(project.id).content) +
                  project.invariants.fold<int>(
                      0,
                      (sum, invariant) =>
                          sum +
                          estimateTokenCount(invariant.name) +
                          estimateTokenCount(invariant.description)) +
                  chat.contextMessages.fold<int>(
                    0,
                    (sum, message) =>
                        sum +
                        (message.tokenCount ??
                            estimateTokenCount(message.content)),
                  ) +
                  ((_generating && _streamingText.isNotEmpty)
                      ? estimateTokenCount(_streamingText)
                      : 0);
          final periodicGenerating =
              widget.repository.isChatScheduleGenerating(chat.id);
          final generating = _generating || periodicGenerating;
          final contextLimit = agent.model.providerId == 'ollama'
              ? chat.contextWindow
              : agent.model.contextWindowTokens;
          final contextProgress =
              (totalTokens / contextLimit).clamp(0.0, 1.0).toDouble();
          final wideHeader = MediaQuery.sizeOf(context).width >= 1000;
          final hasSummary = chat.compressionEnabled &&
              chat.contextSummary.isNotEmpty &&
              chat.summarizedMessageCount > 0;
          final stickyFactsActive = !chat.isPeriodic &&
              chat.contextStrategy == ContextStrategy.stickyFacts;
          final slidingExcludedCount =
              chat.contextStrategy == ContextStrategy.slidingWindow &&
                      chat.messages.length > chat.windowSize
                  ? chat.messages.length - chat.windowSize
                  : 0;
          final hasSlidingHistory = slidingExcludedCount > 0;
          final showOriginals =
              _expandedSummaryCount == chat.summarizedMessageCount;
          final showUnusedWindow = _expandedWindowCount == slidingExcludedCount;
          final hiddenCount = hasSummary && !showOriginals
              ? chat.summarizedMessageCount
              : hasSlidingHistory && !showUnusedWindow
                  ? slidingExcludedCount
                  : 0;
          final summaryItems = hasSummary ? 1 : 0;
          final windowItems = hasSlidingHistory ? 1 : 0;
          final contextItems = summaryItems + windowItems;
          final historyItems =
              chat.messages.length - hiddenCount + contextItems;
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 108,
              title: Padding(
                padding: EdgeInsets.only(right: wideHeader ? 64 : 0),
                child: Row(children: [
                  Expanded(
                      flex: 2,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chat.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                                '${agent.name} · ${project.title} · ${task.title} · ${agent.model.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF667085))),
                            const SizedBox(height: 3),
                            Row(children: [
                              const Text('Состояние задачи: ',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF667085))),
                              Expanded(
                                child: Text(
                                  taskState == null
                                      ? 'не настроено'
                                      : widget.repository.isTaskComplete(task)
                                          ? '${taskState.name} · завершено'
                                          : taskState.name,
                                  key: const Key('chatTaskState'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: taskState == null
                                        ? const Color(0xFF667085)
                                        : Color(taskState.colorValue),
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 5),
                            Semantics(
                              label:
                                  'Использовано $totalTokens из $contextLimit токенов',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  key: const Key('chatTokenProgress'),
                                  value: contextProgress,
                                  minHeight: 5,
                                  backgroundColor: const Color(0xFFE1E6EF),
                                  color: contextProgress >= 0.9
                                      ? const Color(0xFFD92D20)
                                      : contextProgress >= 0.75
                                          ? const Color(0xFFF79009)
                                          : const Color(0xFF3659D9),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Использовано ${formatTokenNumber(totalTokens)} из ${formatTokenNumber(contextLimit)} токенов',
                              key: const Key('chatTotalTokens'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ])),
                  if (wideHeader) ...[
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 64,
                        child: _contextSettings(chat),
                      ),
                    ),
                  ],
                ]),
              ),
              bottom: wideHeader
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(80),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                            height: 112, child: _contextSettings(chat)),
                      ),
                    ),
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final factsOnRight =
                      stickyFactsActive && constraints.maxWidth >= 1000;
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: stickyFactsActive ? 1240 : 920),
                      child: Row(children: [
                        Expanded(
                          child: Column(children: [
                            if (stickyFactsActive && !factsOnRight)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: _factsBlock(chat),
                              ),
                            Expanded(
                              child: chat.messages.isEmpty && !generating
                                  ? _emptyChat(agent)
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 20, 16, 12),
                                      itemCount: historyItems +
                                          ((generating ||
                                                  _streamingText.isNotEmpty)
                                              ? 1
                                              : 0),
                                      itemBuilder: (context, index) {
                                        if (index == historyItems) {
                                          return _bubble(
                                            ChatRole.assistant,
                                            _streamingText,
                                            streaming: true,
                                          );
                                        }
                                        if (hasSummary && index == 0) {
                                          return _summaryBlock(
                                              chat, showOriginals);
                                        }
                                        if (hasSlidingHistory && index == 0) {
                                          return _slidingWindowBlock(
                                              slidingExcludedCount,
                                              showUnusedWindow);
                                        }
                                        final messageIndex =
                                            index - contextItems + hiddenCount;
                                        final message =
                                            chat.messages[messageIndex];
                                        final summarized = hasSummary &&
                                            messageIndex <
                                                chat.summarizedMessageCount;
                                        final outsideWindow =
                                            hasSlidingHistory &&
                                                showUnusedWindow &&
                                                messageIndex <
                                                    slidingExcludedCount;
                                        final bubble = _bubble(
                                          message.role,
                                          message.content,
                                          tokenCount: message.tokenCount,
                                          ragSearch: message.ragSearch,
                                          summarized:
                                              summarized || outsideWindow,
                                          contextLabel: outsideWindow
                                              ? 'Не входит в Sliding Window'
                                              : null,
                                        );
                                        if (summarized &&
                                            messageIndex ==
                                                chat.summarizedMessageCount -
                                                    1) {
                                          return Column(children: [
                                            bubble,
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 16),
                                              child: Row(children: [
                                                Expanded(child: Divider()),
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 12),
                                                  child: Text(
                                                      'Конец сжатой переписки',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                              0xFF667085))),
                                                ),
                                                Expanded(child: Divider()),
                                              ]),
                                            ),
                                          ]);
                                        }
                                        if (outsideWindow &&
                                            messageIndex ==
                                                slidingExcludedCount - 1) {
                                          return Column(children: [
                                            bubble,
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 16),
                                              child: Row(children: [
                                                Expanded(child: Divider()),
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 12),
                                                  child: Text(
                                                      'Конец неиспользуемой истории',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                              0xFF667085))),
                                                ),
                                                Expanded(child: Divider()),
                                              ]),
                                            ),
                                          ]);
                                        }
                                        if (chat.contextStrategy ==
                                                ContextStrategy.branching &&
                                            chat.checkpointMessageCount !=
                                                null &&
                                            messageIndex ==
                                                chat.checkpointMessageCount! -
                                                    1) {
                                          return Column(children: [
                                            bubble,
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 16),
                                              child: Row(children: [
                                                Expanded(child: Divider()),
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 12),
                                                  child: Text(
                                                      'Checkpoint веток',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                              0xFF667085))),
                                                ),
                                                Expanded(child: Divider()),
                                              ]),
                                            ),
                                          ]);
                                        }
                                        return bubble;
                                      },
                                    ),
                            ),
                            if (_error != null)
                              Container(
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F0),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFFDA29B)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline,
                                      color: Color(0xFFB42318)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_error!)),
                                  TextButton(
                                    key: const Key('retryMessageButton'),
                                    onPressed: () =>
                                        _send(addUserMessage: false),
                                    child: const Text('Повторить'),
                                  ),
                                ]),
                              ),
                            _taskStateAction(task, taskState),
                            _composer(),
                          ]),
                        ),
                        if (factsOnRight) ...[
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 300,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(top: 20, right: 16),
                                child: _factsBlock(chat),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );

  Widget _taskStateAction(AgentTask task, TaskStateDefinition? currentState) {
    final nextState = widget.repository.nextStateForTask(task);
    final chat = widget.repository.chatById(widget.chatId);
    final hasLlmResult = chat != null &&
        chat.messages.isNotEmpty &&
        chat.messages.last.role == ChatRole.assistant;
    final resultAlreadySaved = currentState != null &&
        task.stageResults.any((result) => result.stateId == currentState.id);
    if (currentState == null || !hasLlmResult || resultAlreadySaved) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: FilledButton.icon(
        key: const Key('advanceTaskStateInChat'),
        onPressed: _generating
            ? null
            : () => widget.repository.completeCurrentTaskState(
                  task.id,
                  chat.messages.last.content,
                ),
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text(nextState == null
            ? 'Сохранить результат этапа «${currentState.name}»'
            : 'Завершить «${currentState.name}» и перейти в «${nextState.name}»'),
      ),
    );
  }

  Widget _slidingWindowBlock(int hiddenCount, bool showUnused) => Container(
        key: const Key('chatSlidingWindowSummary'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.filter_alt_outlined, color: Color(0xFFC2410C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sliding Window · $hiddenCount сообщений не используются',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Эти сообщения сохранены в истории, но не передаются модели.',
              style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('toggleSlidingWindowMessages'),
              onPressed: () => setState(() {
                _expandedWindowCount = showUnused ? null : hiddenCount;
              }),
              icon: Icon(showUnused ? Icons.expand_less : Icons.expand_more),
              label: Text(showUnused
                  ? 'Скрыть неиспользуемые сообщения'
                  : 'Показать неиспользуемые сообщения'),
            ),
          ],
        ),
      );

  Widget _factsBlock(AgentChat chat) => Container(
        key: const Key('chatFactsBlock'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFABEFC6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.push_pin_outlined, color: Color(0xFF067647)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Sticky Facts · автоматические факты чата',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                key: const Key('refreshFactsButton'),
                tooltip: 'Пересобрать facts из переписки',
                visualDensity: VisualDensity.compact,
                onPressed: _generating ||
                        !chat.messages
                            .any((message) => message.role == ChatRole.user)
                    ? null
                    : () => unawaited(_refreshFacts()),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ]),
            const SizedBox(height: 10),
            if (chat.facts.isEmpty)
              const Text('Факты появятся после первого сообщения.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF667085)))
            else
              ...chat.facts.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(entry.value),
                      ],
                    ),
                  )),
          ],
        ),
      );

  Widget _summaryBlock(AgentChat chat, bool showOriginals) => Container(
        key: const Key('chatContextSummary'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCDD5F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.summarize_outlined, color: Color(0xFF3659D9)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                'Резюме переписки · ${chat.summarizedMessageCount} сообщений',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )),
            ]),
            const SizedBox(height: 10),
            MarkdownBody(
                data: chat.contextSummary,
                selectable: true,
                softLineBreak: true),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('toggleSummarizedMessages'),
              onPressed: () => setState(() {
                _expandedSummaryCount =
                    showOriginals ? null : chat.summarizedMessageCount;
              }),
              icon: Icon(showOriginals ? Icons.expand_less : Icons.expand_more),
              label: Text(showOriginals
                  ? 'Скрыть исходные сообщения'
                  : 'Показать исходные сообщения'),
            ),
          ],
        ),
      );

  Widget _contextSettings(AgentChat chat) {
    final running = widget.repository.isChatScheduleRunning(chat.id);
    final periodic = chat.isPeriodic;
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      child: Form(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
              child: Center(
                  child: FilledButton.tonalIcon(
            key: const Key('chatSettingsButton'),
            onPressed: _isGenerating ? null : () => _editChatSettings(chat),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Настройки чата'),
          ))),
          const VerticalDivider(width: 20, indent: 4, endIndent: 4),
          Expanded(
              child: Row(children: [
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Расписание',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    periodic
                        ? 'Каждые ${chat.scheduleInterval} ${_scheduleUnitLabel(chat.scheduleUnit)}'
                        : 'Не настроено',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ])),
            IconButton(
                key: const Key('editChatSchedule'),
                tooltip: 'Настроить расписание',
                onPressed: () => _editChatSchedule(chat),
                icon: Icon(Icons.edit_calendar_outlined,
                    color: periodic ? const Color(0xFF3659D9) : null)),
            IconButton.filledTonal(
              key: Key(running
                  ? 'stopChatSchedule-${chat.id}'
                  : 'startChatSchedule-${chat.id}'),
              tooltip:
                  running ? 'Остановить расписание' : 'Запустить расписание',
              onPressed: !periodic
                  ? null
                  : () {
                      if (running) {
                        widget.repository.stopChatSchedule(chat.id);
                      } else {
                        widget.repository
                            .startChatSchedule(chat.id, widget.provider);
                      }
                    },
              icon:
                  Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _strategySettings(AgentChat chat) {
    String? validate(String? _) {
      final max = int.tryParse(_maxController.text);
      final min = int.tryParse(_minController.text);
      return max == null || min == null || min < 1 || min >= max
          ? 'Нужно: 1 ≤ min < max'
          : null;
    }

    void save(String _) {
      if (!(_compressionForm.currentState?.validate() ?? false)) return;
      widget.repository.updateCompressionSettings(chat.id,
          enabled: chat.compressionEnabled,
          max: int.parse(_maxController.text),
          min: int.parse(_minController.text));
    }

    final periodic = chat.isPeriodic;
    return Form(
        key: _compressionForm,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 2),
              child: Text('Стратегия сжатия')),
          DropdownButtonHideUnderline(
            child: DropdownButton<ContextStrategy>(
              key: const Key('contextStrategyDropdown'),
              value: chat.contextStrategy,
              isExpanded: true,
              isDense: true,
              items: ContextStrategy.values
                  .map((strategy) => DropdownMenuItem(
                        value: strategy,
                        child: Text(_strategyTitle(strategy),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _isGenerating || periodic
                  ? null
                  : (strategy) {
                      if (strategy != null) {
                        unawaited(_selectContextStrategy(chat, strategy));
                      }
                    },
            ),
          ),
          if (!periodic && chat.contextStrategy == ContextStrategy.compression)
            Row(children: [
              Expanded(
                  child: _numberField(
                      key: const Key('compressionMaxField'),
                      controller: _maxController,
                      label: 'max',
                      enabled: chat.compressionEnabled && !_isGenerating,
                      validator: validate,
                      onChanged: save)),
              const SizedBox(width: 6),
              Expanded(
                  child: _numberField(
                      key: const Key('compressionMinField'),
                      controller: _minController,
                      label: 'min',
                      enabled: chat.compressionEnabled && !_isGenerating,
                      validator: validate,
                      onChanged: save)),
            ])
          else if (chat.contextStrategy == ContextStrategy.slidingWindow ||
              (!periodic &&
                  chat.contextStrategy == ContextStrategy.stickyFacts))
            _numberField(
                key: const Key('contextWindowSizeField'),
                controller: _windowController,
                label: 'Последние N',
                enabled: !periodic && !_isGenerating,
                onChanged: (_) {
                  final value = int.tryParse(_windowController.text);
                  if (value != null && value >= 1 && value <= 200) {
                    widget.repository.updateWindowSize(chat.id, value);
                  }
                })
          else if (!periodic &&
              chat.contextStrategy == ContextStrategy.branching)
            _branchControls(chat),
        ]));
  }

  Future<void> _editChatSettings(AgentChat initialChat) async {
    final temperature =
        TextEditingController(text: '${initialChat.temperature}');
    final maxTokens = TextEditingController(text: '${initialChat.maxTokens}');
    final contextWindow =
        TextEditingController(text: '${initialChat.contextWindow}');
    final form = GlobalKey<FormState>();
    final task = widget.repository.taskById(initialChat.taskId);
    final agent =
        widget.repository.agentById(task?.agentId ?? initialChat.agentId);
    final local = agent?.model.providerId == 'ollama';
    if (!local) {
      contextWindow.text =
          '${agent?.model.contextWindowTokens ?? initialChat.contextWindow}';
    }
    final route = DialogRoute<void>(
        context: context,
        builder: (dialogContext) => AnimatedBuilder(
            animation: widget.repository,
            builder: (context, _) {
              final chat =
                  widget.repository.chatById(initialChat.id) ?? initialChat;
              return AlertDialog(
                title: const Text('Настройки чата'),
                content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          _strategySettings(chat),
                          const SizedBox(height: 8),
                          const Text('Изменения стратегии применяются сразу.',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF667085))),
                          const SizedBox(height: 20),
                          Form(
                              key: form,
                              child: Column(children: [
                                TextFormField(
                                    key: const Key('chatTemperatureField'),
                                    controller: temperature,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Температура',
                                        helperText: 'От 0 до 2'),
                                    validator: (text) {
                                      final value = double.tryParse(
                                          (text ?? '').replaceAll(',', '.'));
                                      return value == null ||
                                              !value.isFinite ||
                                              value < 0 ||
                                              value > 2
                                          ? 'Введите число от 0 до 2'
                                          : null;
                                    }),
                                const SizedBox(height: 12),
                                TextFormField(
                                    key: const Key('chatMaxTokensField'),
                                    controller: maxTokens,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Max tokens',
                                        helperText:
                                            'Максимальная длина ответа'),
                                    validator: (text) {
                                      final value = int.tryParse(text ?? '');
                                      final window =
                                          int.tryParse(contextWindow.text);
                                      return value == null ||
                                              value < 1 ||
                                              value > 65536 ||
                                              (local &&
                                                  window != null &&
                                                  value >= window)
                                          ? 'От 1 до 65536, меньше Context window'
                                          : null;
                                    }),
                                const SizedBox(height: 12),
                                TextFormField(
                                    key: const Key('chatContextWindowField'),
                                    controller: contextWindow,
                                    enabled: local,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                        labelText: 'Context window',
                                        helperText: local
                                            ? 'Размер контекста в токенах: от 128 до 1000000'
                                            : 'Определяется облачной моделью: ${agent?.model.contextWindowTokens}'),
                                    validator: (text) {
                                      final value = int.tryParse(text ?? '');
                                      return local &&
                                              (value == null ||
                                                  value < 128 ||
                                                  value > 1000000)
                                          ? 'От 128 до 1000000'
                                          : null;
                                    }),
                              ])),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Закрыть')),
                  FilledButton(
                      key: const Key('saveChatSettingsButton'),
                      onPressed: () {
                        if (!form.currentState!.validate() ||
                            !(_compressionForm.currentState?.validate() ??
                                true)) {
                          return;
                        }
                        widget.repository.updateChatGenerationSettings(chat.id,
                            temperature: double.parse(
                                temperature.text.replaceAll(',', '.')),
                            maxTokens: int.parse(maxTokens.text),
                            contextWindow: int.parse(contextWindow.text));
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Сохранить'))
                ],
              );
            }));
    await Navigator.of(context).push(route);
    await route.completed;
    temperature.dispose();
    maxTokens.dispose();
    contextWindow.dispose();
  }

  String _scheduleUnitLabel(String unit) => switch (unit) {
        'seconds' => 'сек.',
        'minutes' => 'мин.',
        'days' => 'дн.',
        _ => 'ч.',
      };

  Future<void> _editChatSchedule(AgentChat chat) async {
    final prompt = TextEditingController(text: chat.schedulePrompt);
    final interval = TextEditingController(text: '${chat.scheduleInterval}');
    var unit = chat.scheduleUnit;
    final result =
        await showDialog<({String prompt, int interval, String unit})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: const Text('Расписание чата'),
                content: SizedBox(
                    width: 520,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: prompt,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              labelText: 'Запрос пользователя',
                              hintText:
                                  'Будет повторно отправляться по расписанию')),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: interval,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Период'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          decoration:
                              const InputDecoration(labelText: 'Единица'),
                          items: const [
                            DropdownMenuItem(
                                value: 'seconds', child: Text('Секунды')),
                            DropdownMenuItem(
                                value: 'minutes', child: Text('Минуты')),
                            DropdownMenuItem(
                                value: 'hours', child: Text('Часы')),
                            DropdownMenuItem(value: 'days', child: Text('Дни')),
                          ],
                          onChanged: (value) {
                            if (value != null) refresh(() => unit = value);
                          },
                        )),
                      ]),
                      const SizedBox(height: 8),
                      const Text(
                          'Для периодического чата автоматически включается Sliding Window с одним сообщением.',
                          style: TextStyle(
                              color: Color(0xFF667085), fontSize: 12)),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () {
                        final value = int.tryParse(interval.text.trim());
                        if (value == null || value < 1 || value > 100000) {
                          return;
                        }
                        Navigator.pop(dialogContext, (
                          prompt: prompt.text.trim(),
                          interval: value,
                          unit: unit
                        ));
                      },
                      child: const Text('Сохранить')),
                ],
              )),
    );
    prompt.dispose();
    interval.dispose();
    if (result != null) {
      widget.repository.updateChatSchedule(chat.id,
          prompt: result.prompt, interval: result.interval, unit: result.unit);
      if (result.prompt.isNotEmpty) _windowController.text = '1';
    }
  }

  String _strategyTitle(ContextStrategy strategy) => switch (strategy) {
        ContextStrategy.fullHistory => 'Полная история',
        ContextStrategy.compression => 'Compression',
        ContextStrategy.slidingWindow => 'Sliding Window',
        ContextStrategy.stickyFacts => 'Sticky Facts',
        ContextStrategy.branching => 'Branching',
      };

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool enabled,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) =>
      TextFormField(
        key: key,
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            errorStyle: const TextStyle(fontSize: 10)),
        validator: validator,
        onChanged: onChanged,
      );

  Widget _branchControls(AgentChat chat) {
    if (chat.branches.isEmpty) {
      return FilledButton.tonalIcon(
        key: const Key('createBranchesButton'),
        onPressed: _generating
            ? null
            : () => widget.repository.createBranches(chat.id),
        icon: const Icon(Icons.call_split, size: 18),
        label: const Text('Создать 2 ветки'),
      );
    }
    return DropdownButton<String>(
      key: const Key('activeBranchDropdown'),
      value: chat.activeBranchId,
      isExpanded: true,
      items: chat.branches
          .map((branch) => DropdownMenuItem(
                value: branch.id,
                child: Text(branch.name),
              ))
          .toList(),
      onChanged: _generating
          ? null
          : (id) {
              if (id != null) {
                setState(() => _expandedSummaryCount = null);
                widget.repository.switchBranch(chat.id, id);
                _scrollToEnd();
              }
            },
    );
  }

  Widget _emptyChat(AiAgent agent) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.waving_hand_outlined,
                size: 44, color: Color(0xFF3659D9)),
            const SizedBox(height: 14),
            Text('Начните диалог с ${agent.name}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Системные инструкции будут добавлены автоматически.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667085))),
          ]),
        ),
      );

  Widget _bubble(
    ChatRole role,
    String content, {
    bool streaming = false,
    bool summarized = false,
    String? contextLabel,
    int? tokenCount,
    Map<String, dynamic>? ragSearch,
  }) {
    final isUser = role == ChatRole.user;
    final displayedTokens = tokenCount ?? estimateTokenCount(content);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: summarized
              ? const Color(0xFFF0F2F5)
              : isUser
                  ? const Color(0xFF3659D9)
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: summarized
              ? Border.all(color: const Color(0xFFCBD2DC))
              : isUser
                  ? null
                  : Border.all(color: const Color(0xFFE1E6EF)),
        ),
        child: streaming && content.isEmpty
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(_compressing
                    ? (_factsUpdater != null
                        ? 'Обновляю facts…'
                        : 'Сжимаю контекст…')
                    : 'Генерирую ответ…'),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summarized) ...[
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 14, color: Color(0xFF667085)),
                      const SizedBox(width: 6),
                      Text(contextLabel ?? 'Включено в резюме',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF667085))),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  if (isUser)
                    SelectableText(content,
                        style: TextStyle(
                            color: summarized
                                ? const Color(0xFF344054)
                                : Colors.white,
                            height: 1.45))
                  else
                    MarkdownBody(
                      data: content,
                      selectable: true,
                      softLineBreak: true,
                      onTapLink: (_, href, __) {
                        final uri = href == null ? null : Uri.tryParse(href);
                        if (uri != null &&
                            (uri.scheme == 'http' || uri.scheme == 'https')) {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  if (isUser && ragSearch != null)
                    TextButton.icon(
                      key: Key('showRewrittenQuery-$content'),
                      style: TextButton.styleFrom(
                          foregroundColor: summarized
                              ? const Color(0xFF344054)
                              : Colors.white),
                      icon: const Icon(Icons.manage_search, size: 18),
                      label: const Text('Поисковый запрос'),
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                                title: Text(ragSearch['rewrittenQuery'] != null
                                    ? 'Переформулированный запрос'
                                    : 'Поиск по RAG'),
                                content: SizedBox(
                                    width: 560,
                                    child: SingleChildScrollView(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          SelectableText(
                                              (ragSearch['rewrittenQuery'] ??
                                                  ragSearch['originalQuery'] ??
                                                  content) as String),
                                          const SizedBox(height: 16),
                                          for (final search
                                              in (ragSearch['searches']
                                                      as List? ??
                                                  []))
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Text(
                                                    '${search['ragName']}: отобрано ${search['selectedCount']} из ${search['candidateCount']} фрагментов, передано модели ${search['deliveredCount'] ?? search['selectedCount']}.\nЗапрос: ${search['query']}\n${search['selectedCount'] == 0 ? 'Нет фрагментов, прошедших настройки отбора.' : ''}')),
                                        ]))),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Закрыть'))
                                ],
                              )),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    formatTokenCount(displayedTokens),
                    key: streaming ? const Key('streamingMessageTokens') : null,
                    style: TextStyle(
                      color: summarized
                          ? const Color(0xFF667085)
                          : isUser
                              ? Colors.white.withValues(alpha: 0.72)
                              : const Color(0xFF98A2B3),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FB),
          border: Border(top: BorderSide(color: Color(0xFFE1E6EF))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                key: const Key('chatMessageField'),
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                enabled: !_isGenerating,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Введите сообщение…',
                  helperText: 'Enter — отправить, Shift + Enter — новая строка',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_isGenerating)
            IconButton.filled(
              key: const Key('stopGenerationButton'),
              tooltip: 'Остановить генерацию',
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded),
            )
          else
            IconButton.filled(
              key: const Key('sendMessageButton'),
              tooltip: 'Отправить',
              onPressed: _send,
              icon: const Icon(Icons.send_rounded),
            ),
        ]),
      );
}
