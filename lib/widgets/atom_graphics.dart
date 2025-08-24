// lib/widgets/atom_graphics.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Main animated atom tap target
class AtomGraphic extends StatefulWidget {
  const AtomGraphic({super.key, required this.size, this.reduceAnimations = false});
  final double size;
  final bool reduceAnimations;

  @override
  State<AtomGraphic> createState() => _AtomGraphicState();
}

class _AtomGraphicState extends State<AtomGraphic> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _timeSeconds = 0.0;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceAnimations) {
      _ticker ??= createTicker((elapsed) {
        if (!mounted) return;
        setState(() => _timeSeconds = elapsed.inMicroseconds / 1e6);
      })..start();
    }
  }

  @override
  void didUpdateWidget(covariant AtomGraphic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceAnimations != widget.reduceAnimations) {
      if (widget.reduceAnimations) {
        _ticker?.dispose();
        _ticker = null;
      } else {
        _ticker ??= createTicker((elapsed) {
          if (!mounted) return;
          setState(() => _timeSeconds = elapsed.inMicroseconds / 1e6);
        })..start();
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _AtomPainter(timeSeconds: _timeSeconds, reduce: widget.reduceAnimations),
    );
  }
}

class _AtomPainter extends CustomPainter {
  final double timeSeconds;
  final bool reduce;
  _AtomPainter({required this.timeSeconds, required this.reduce});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.45;

    // Nucleus (soft glow)
    final nucleusPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFB388FF), const Color(0xFF7C4DFF)],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.22))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius * 0.18, nucleusPaint);

    // Orbit paint with a soft glow
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.04
      ..color = const Color(0x80FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);

    // Base ellipse
    final orbitRect = Rect.fromCenter(center: center, width: radius * 1.8, height: radius * 1.05);

    // Draw 3 tilted ellipses
    for (final tiltDeg in [0.0, 60.0, 120.0]) {
      final tilt = tiltDeg * pi / 180;
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(tilt)
        ..translate(-center.dx, -center.dy)
        ..drawOval(orbitRect, orbitPaint)
        ..restore();
    }

    // Electrons (glow)
    final electronPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    void drawElectron({
      required double angularSpeed, // radians per second
      required double tiltDeg,
      required double phase,       // radians
      double scale = 1.0,
    }) {
      final tilt = tiltDeg * pi / 180;
      final a = (orbitRect.width / 2) * scale;
      final b = (orbitRect.height / 2) * scale;

      final theta = reduce ? phase : angularSpeed * timeSeconds + phase; // static if reduced
      final x = a * cos(theta);
      final y = b * sin(theta);

      final xr = x * cos(tilt) - y * sin(tilt);
      final yr = x * sin(tilt) + y * cos(tilt);
      final pos = Offset(center.dx + xr, center.dy + yr);

      canvas.drawCircle(pos, radius * 0.08, electronPaint);
    }

    drawElectron(angularSpeed: 1.8, tiltDeg:   0, phase: 0.0,      scale: 0.98);
    drawElectron(angularSpeed: 2.3, tiltDeg:  60, phase: pi / 3,   scale: 0.98);
    drawElectron(angularSpeed: 2.8, tiltDeg: 120, phase: 2 * pi/3, scale: 0.98);
  }

  @override
  bool shouldRepaint(covariant _AtomPainter oldDelegate) =>
      oldDelegate.timeSeconds != timeSeconds || oldDelegate.reduce != reduce;
}

/// MiniAtom painter used elsewhere as a static graphic
class MiniAtom extends StatelessWidget {
  const MiniAtom({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _MiniAtomPainter());
  }
}

class _MiniAtomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.5;

    // Nucleus
    final nucleus = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFFB388FF), Color(0xFF7C4DFF)],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.7))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, r * 0.45, nucleus);

    // Orbits (static, faint)
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.18
      ..color = const Color(0x66FFFFFF);
    final rect = Rect.fromCenter(center: center, width: r * 1.6, height: r * 0.9);
    for (final tiltDeg in [0.0, 60.0, 120.0]) {
      final tilt = tiltDeg * pi / 180;
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(tilt)
        ..translate(-center.dx, -center.dy)
        ..drawOval(rect, orbit)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MiniAtomPainter oldDelegate) => false;
}
