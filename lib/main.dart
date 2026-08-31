import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const DeepSeekChatApp());
}

class DeepSeekChatApp extends StatelessWidget {
  const DeepSeekChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepSeek Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DFEA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DFEA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF2563EB), width: 1.5),
          ),
        ),
      ),
      home: const ChatPage(),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000/api/chat',
  );
  final _messages = <ChatMessage>[];
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: content));
      _inputController.clear();
      _error = null;
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': _messages.map((message) => message.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final answer = _decodeAnswer(response.body);
        setState(
          () => _messages.add(ChatMessage(role: 'assistant', content: answer)),
        );
      } else {
        setState(() => _error = _decodeError(response.body));
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'Сервер слишком долго отвечает. Попробуйте еще раз.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось связаться с сервером. Проверьте, что backend запущен.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
        _inputFocusNode.requestFocus();
      }
    }
  }

  String _decodeAnswer(String body) {
    final payload = jsonDecode(body);
    final reply = payload is Map<String, dynamic> ? payload['reply'] : null;
    if (reply is! String) throw const FormatException();
    return reply;
  }

  String _decodeError(String body) {
    try {
      final payload = jsonDecode(body);
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      return error is String ? error : 'Не удалось получить ответ от сервера.';
    } on FormatException {
      return 'Не удалось получить ответ от сервера.';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              children: [
                const _Header(),
                Expanded(
                  child: _MessageList(
                    messages: _messages,
                    scrollController: _scrollController,
                    isLoading: _isLoading,
                  ),
                ),
                if (_error != null) _ErrorBanner(message: _error!),
                _Composer(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  isLoading: _isLoading,
                  onSend: _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
    child: Row(
      children: [
        Icon(Icons.auto_awesome_rounded, color: Color(0xFF2563EB)),
        SizedBox(width: 10),
        Text(
          'DeepSeek Agent',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.isLoading,
  });
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final bool isLoading;
  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 46,
                color: Color(0xFF94A3B8),
              ),
              SizedBox(height: 16),
              Text(
                'Начните разговор',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Спросите что-нибудь у ИИ-агента',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: messages.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return const _TypingIndicator();
        return _MessageBubble(message: messages[index]);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isUser ? null : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            height: 1.4,
            color: isUser ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.only(top: 10),
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFFB91C1C))),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !isLoading,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(
              hintText: 'Напишите сообщение...',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: isLoading ? null : onSend,
          tooltip: 'Отправить',
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    ),
  );
}
