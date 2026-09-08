import 'package:flutter/material.dart';

class AppSurface extends StatelessWidget {
  const AppSurface(
      {required this.child,
      this.padding = const EdgeInsets.all(20),
      super.key});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE1E6EF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A162033),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
