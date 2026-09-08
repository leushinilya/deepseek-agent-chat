import 'package:flutter/material.dart';

import 'agents/repository.dart';
import 'pages/app_shell.dart';

void main() => runApp(const DeepSeekComparisonApp());

class DeepSeekComparisonApp extends StatelessWidget {
  const DeepSeekComparisonApp({super.key, this.repository});

  final AgentChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Сравнение AI-моделей',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3659D9),
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: Color(0xFF172033)),
          titleLarge: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF172033)),
          bodyMedium: TextStyle(height: 1.5, color: Color(0xFF344054)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFFD8DEEA))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFFD8DEEA))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFF3659D9), width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFFB42318))),
          contentPadding: EdgeInsets.all(16),
        ),
        filledButtonTheme: const FilledButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(Color(0xFF3659D9)),
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 22, vertical: 17)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)))),
          ),
        ),
      ),
      home: _AppLoader(
        repository:
            repository ?? AgentChatRepository(SharedPreferencesKeyValueStore()),
      ),
    );
  }
}

class _AppLoader extends StatefulWidget {
  const _AppLoader({required this.repository});
  final AgentChatRepository repository;

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  @override
  void initState() {
    super.initState();
    widget.repository.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.repository,
        builder: (context, _) {
          if (!widget.repository.isLoaded) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Stack(children: [
            AppShell(repository: widget.repository),
            if (widget.repository.loadError != null)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Material(
                  color: const Color(0xFFFFF1F0),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFB42318)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.repository.loadError!)),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      );
}
