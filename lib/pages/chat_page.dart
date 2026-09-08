import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agents/llm_provider.dart';
import '../agents/models.dart';
import '../agents/repository.dart';

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

  @override
  void dispose() {
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
    });
    _scrollToEnd();
    final operation = widget.provider.send(
      LlmRequest(agent: agent, messages: updatedChat.messages),
    );
    _operation = operation;
    _subscription = operation.events.listen(
      (event) {
        if (!mounted) return;
        if (event is LlmTextDelta) {
          setState(() => _streamingText += event.text);
          _scrollToEnd();
        } else if (event is LlmDone) {
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
      widget.repository
          .appendMessage(widget.chatId, ChatRole.assistant, answer);
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
          return Scaffold(
            appBar: AppBar(
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${agent.name} · ${agent.model.title}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF667085))),
                  ]),
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
                              itemCount: chat.messages.length +
                                  ((_generating || _streamingText.isNotEmpty)
                                      ? 1
                                      : 0),
                              itemBuilder: (context, index) {
                                if (index == chat.messages.length) {
                                  return _bubble(
                                    ChatRole.assistant,
                                    _streamingText,
                                    streaming: true,
                                  );
                                }
                                final message = chat.messages[index];
                                return _bubble(message.role, message.content);
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

  Widget _bubble(ChatRole role, String content, {bool streaming = false}) {
    final isUser = role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF3659D9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: const Color(0xFFE1E6EF)),
        ),
        child: streaming && content.isEmpty
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Генерирую ответ…'),
              ])
            : isUser
                ? SelectableText(content,
                    style: const TextStyle(color: Colors.white, height: 1.45))
                : MarkdownBody(
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
