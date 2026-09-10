import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agents/llm_provider.dart';
import '../agents/context_compressor.dart';
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
  bool _compressing = false;
  int? _expandedSummaryCount;
  final _compressionForm = GlobalKey<FormState>();
  late final TextEditingController _maxController;
  late final TextEditingController _minController;

  @override
  void initState() {
    super.initState();
    final chat = widget.repository.chatById(widget.chatId);
    _maxController =
        TextEditingController(text: '${chat?.compressionMax ?? 20}');
    _minController =
        TextEditingController(text: '${chat?.compressionMin ?? 6}');
  }

  @override
  void dispose() {
    _maxController.dispose();
    _minController.dispose();
    _compressor?.cancel();
    _operation?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send({bool addUserMessage = true}) async {
    if (_generating) return;
    final chat = widget.repository.chatById(widget.chatId);
    if (chat == null) return;
    if (!(_compressionForm.currentState?.validate() ?? true)) return;
    final agent = widget.repository.agentById(chat.agentId);
    if (agent == null) {
      setState(() => _error = 'Агент этого чата больше недоступен.');
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
    final contextChat = widget.repository.chatById(widget.chatId);
    if (contextChat == null || !mounted) return;
    final operation = widget.provider.send(
      LlmRequest(
          agent: agent,
          messages: contextChat.contextMessages,
          summary: contextChat.activeSummary),
    );
    _operation = operation;
    _subscription = operation.events.listen(
      (event) {
        if (!mounted) return;
        if (event is LlmTextDelta) {
          setState(() => _streamingText += event.text);
          _scrollToEnd();
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
    if (_compressing) {
      _compressor?.cancel();
      return;
    }
    _operation?.cancel();
    _subscription?.cancel();
    _finish();
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
          final agent =
              chat == null ? null : widget.repository.agentById(chat.agentId);
          if (chat == null || agent == null) {
            return const Scaffold(
              body: Center(child: Text('Чат или агент недоступен.')),
            );
          }
          final totalTokens = chat.messages.isEmpty
              ? 0
              : estimateTokenCount(agent.systemPrompt) +
                  estimateTokenCount(chat.activeSummary) +
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
          final contextLimit = agent.model.contextWindowTokens;
          final contextProgress =
              (totalTokens / contextLimit).clamp(0.0, 1.0).toDouble();
          final wideHeader = MediaQuery.sizeOf(context).width >= 760;
          final hasSummary = chat.compressionEnabled &&
              chat.contextSummary.isNotEmpty &&
              chat.summarizedMessageCount > 0;
          final showOriginals =
              _expandedSummaryCount == chat.summarizedMessageCount;
          final hiddenCount =
              hasSummary && !showOriginals ? chat.summarizedMessageCount : 0;
          final summaryItems = hasSummary ? 1 : 0;
          final historyItems =
              chat.messages.length - hiddenCount + summaryItems;
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 92,
              title: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(chat.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${agent.name} · ${agent.model.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF667085))),
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
                  SizedBox(width: 380, child: _compressionSettings(chat)),
                ],
              ]),
              bottom: wideHeader
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(82),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                            height: 82, child: _compressionSettings(chat)),
                      ),
                    ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(children: [
                    Expanded(
                      child: chat.messages.isEmpty && !_generating
                          ? _emptyChat(agent)
                          : ListView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 20, 16, 12),
                              itemCount: historyItems +
                                  ((_generating || _streamingText.isNotEmpty)
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
                                  return _summaryBlock(chat, showOriginals);
                                }
                                final messageIndex =
                                    index - summaryItems + hiddenCount;
                                final message = chat.messages[messageIndex];
                                final summarized = hasSummary &&
                                    messageIndex < chat.summarizedMessageCount;
                                final bubble = _bubble(
                                  message.role,
                                  message.content,
                                  tokenCount: message.tokenCount,
                                  summarized: summarized,
                                );
                                if (summarized &&
                                    messageIndex ==
                                        chat.summarizedMessageCount - 1) {
                                  return Column(children: [
                                    bubble,
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: Row(children: [
                                        Expanded(child: Divider()),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Text('Конец сжатой переписки',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF667085))),
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
                          border: Border.all(color: const Color(0xFFFDA29B)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFB42318)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!)),
                          TextButton(
                            key: const Key('retryMessageButton'),
                            onPressed: () => _send(addUserMessage: false),
                            child: const Text('Повторить'),
                          ),
                        ]),
                      ),
                    _composer(),
                  ]),
                ),
              ),
            ),
          );
        },
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

  Widget _compressionSettings(AgentChat chat) {
    String? validate(String? _) {
      if (!chat.compressionEnabled) return null;
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

    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      child: Form(
        key: _compressionForm,
        child: Row(children: [
          Tooltip(
            message: 'При достижении max ранняя переписка заменяется резюме. '
                'Последние min сообщений сохраняются полностью.'
                '${chat.contextSummary.isEmpty ? '' : '\nВ резюме: ${chat.summarizedMessageCount} сообщений.'}',
            child: SizedBox(
                width: 132,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_compressing ? 'Сжимаю контекст…' : 'Сжатие контекста',
                        style: const TextStyle(fontSize: 12)),
                    Switch.adaptive(
                      key: const Key('contextCompressionSwitch'),
                      value: chat.compressionEnabled,
                      onChanged: _generating
                          ? null
                          : (enabled) {
                              _maxController.text = '${chat.compressionMax}';
                              _minController.text = '${chat.compressionMin}';
                              widget.repository.updateCompressionSettings(
                                  chat.id,
                                  enabled: enabled,
                                  max: chat.compressionMax,
                                  min: chat.compressionMin);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  _compressionForm.currentState?.validate();
                                }
                              });
                            },
                    ),
                  ],
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Tooltip(
                  message: 'Количество сообщений для запуска сжатия',
                  child: TextFormField(
                    key: const Key('compressionMaxField'),
                    controller: _maxController,
                    enabled: chat.compressionEnabled && !_generating,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                        labelText: 'max',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        errorStyle: TextStyle(fontSize: 10)),
                    validator: validate,
                    onChanged: save,
                  ))),
          const SizedBox(width: 12),
          Expanded(
              child: Tooltip(
                  message: 'Количество последних сообщений без сжатия',
                  child: TextFormField(
                    key: const Key('compressionMinField'),
                    controller: _minController,
                    enabled: chat.compressionEnabled && !_generating,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                        labelText: 'min',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        errorStyle: TextStyle(fontSize: 10)),
                    validator: validate,
                    onChanged: save,
                  ))),
        ]),
      ),
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
    int? tokenCount,
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
                Text(_compressing ? 'Сжимаю контекст…' : 'Генерирую ответ…'),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summarized) ...[
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 14, color: Color(0xFF667085)),
                      SizedBox(width: 6),
                      Text('Включено в резюме',
                          style: TextStyle(
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
                enabled: !_generating,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Введите сообщение…',
                  helperText: 'Enter — отправить, Shift + Enter — новая строка',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_generating)
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
