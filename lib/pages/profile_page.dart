import 'package:flutter/material.dart';

import '../agents/repository.dart';
import '../agents/user_profile.dart';
import '../widgets/app_surface.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.repository, super.key});

  final AgentChatRepository repository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name =
      TextEditingController(text: widget.repository.userProfile.name);
  late final _style =
      TextEditingController(text: widget.repository.userProfile.style);
  late final _format =
      TextEditingController(text: widget.repository.userProfile.format);
  late final _constraints =
      TextEditingController(text: widget.repository.userProfile.constraints);

  @override
  void dispose() {
    _name.dispose();
    _style.dispose();
    _format.dispose();
    _constraints.dispose();
    super.dispose();
  }

  void _save() {
    try {
      widget.repository.updateUserProfile(UserProfile(
        name: _name.text,
        style: _style.text,
        format: _format.text,
        constraints: _constraints.text,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(error.message?.toString() ?? 'Проверьте поля профиля.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Профиль пользователя',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'Эти настройки учитываются во всех обычных ответах моделей.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                  const SizedBox(height: 22),
                  AppSurface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('profileNameField'),
                            controller: _name,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'Имя',
                              hintText: 'Как к вам обращаться',
                            ),
                          ),
                          const SizedBox(height: 14),
                          _preferenceField(_style, 'profileStyleField', 'Стиль',
                              'Например: дружелюбно, кратко, без канцелярита'),
                          const SizedBox(height: 14),
                          _preferenceField(
                              _format,
                              'profileFormatField',
                              'Формат',
                              'Например: сначала вывод, затем короткий список'),
                          const SizedBox(height: 14),
                          _preferenceField(
                              _constraints,
                              'profileConstraintsField',
                              'Ограничения',
                              'Например: не использовать англицизмы'),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: const Key('saveProfileButton'),
                              onPressed: _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Сохранить профиль'),
                            ),
                          ),
                        ]),
                  ),
                ]),
          ),
        ),
      );

  Widget _preferenceField(TextEditingController controller, String key,
          String label, String hint) =>
      TextField(
        key: Key(key),
        controller: controller,
        minLines: 2,
        maxLines: 5,
        maxLength: 4000,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
        ),
      );
}
