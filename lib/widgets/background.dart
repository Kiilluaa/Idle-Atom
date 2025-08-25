import 'package:flutter/material.dart';

// Simple, reusable background gradient widget that fills all available space.
// Usage: const Background(style: 0|1|2)
class Background extends StatelessWidget {
  const Background({super.key, required this.style});
  final int style;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 1:
        return const SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B0B0F), Color(0xFF1A1B1F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
      case 2:
        return const SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF082032), Color(0xFF1B3B4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
      default:
        return const SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0E27), Color(0xFF1B1F3B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
    }
  }
}