// lib/widgets/fx_layer.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Floating particle/text FX layer for tap feedback.
/// Note: Wrap this with IgnorePointer in your page so it doesn't block taps:
///   if (showFx) IgnorePointer(ignoring: true, child: FloatingFxLayer(key: _fxKey))
class FloatingFxLayer extends StatefulWidget {
  const FloatingFxLayer({super.key});

  @override
  FloatingFxLayerState createState() => FloatingFxLayerState();
}

class FloatingFxLayerState extends State<FloatingFxLayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _time = 0.0; // seconds

  final Random _rng = Random();
  final List<_ArcParticle> _arcParticles = [];
  final List<_FloatText> _floatTexts = [];

  @override
  void initState() {
    super.initState();
    _ticker ??= createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _time = elapsed.inMicroseconds / 1e6;
        _arcParticles.removeWhere((p) => _time - p.t0 >= p.duration);
        _floatTexts.removeWhere((t) => _time - t.t0 >= t.duration);
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Call from parent via global key to spawn one FX at a local coordinate.
  void spawnTapFx(Offset localPos, String text) {
    final now = _time;

    final dirRight = _rng.nextBool() ? 1.0 : -1.0;
    final lateral = _lerp(40, 90, _rng.nextDouble());
    final rise = _lerp(80, 140, _rng.nextDouble());
    final dur = _lerp(0.7, 1.0, _rng.nextDouble());
    final size = _lerp(14, 22, _rng.nextDouble());
    final bow = _lerp(0.3, 0.8, _rng.nextDouble());

    _arcParticles.add(
      _ArcParticle(
        start: localPos,
        control: localPos + Offset(dirRight * lateral * 0.5, -rise * bow),
        end: localPos + Offset(dirRight * lateral, -rise),
        t0: now,
        duration: dur,
        size: size,
      ),
    );

    _floatTexts.add(
      _FloatText(
        start: localPos + const Offset(0, -8),
        end: localPos + const Offset(0, -90),
        t0: now,
        duration: 1.0,
        text: text,
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mini atoms (arc)
        ..._arcParticles.map((p) {
          final t = ((_time - p.t0) / p.duration).clamp(0.0, 1.0);
          Offset lerpQ(Offset a, Offset b, double t) =>
              Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
          final q1 = lerpQ(p.start, p.control, t);
          final q2 = lerpQ(p.control, p.end, t);
          final pos = lerpQ(q1, q2, t);
          final opacity = (1.0 - t);
          return Positioned(
            left: pos.dx,
            top: pos.dy,
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: const Offset(-10, -10),
                child: const _MiniAtomIcon(size: 18),
              ),
            ),
          );
        }),

        // Floating +X text (compact)
        ..._floatTexts.map((ft) {
          final t = ((_time - ft.t0) / ft.duration).clamp(0.0, 1.0);
          final dx = _lerp(ft.start.dx, ft.end.dx, t);
          final dy = _lerp(ft.start.dy, ft.end.dy, t);
          final opacity = (1.0 - t);
          return Positioned(
            left: dx,
            top: dy,
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: const Offset(-8, -8),
                child: Text(
                  ft.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(blurRadius: 6, color: Colors.black, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// Simple visual for FX atom (not the main painter)
class _MiniAtomIcon extends StatelessWidget {
  const _MiniAtomIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [const Color(0xFFB388FF).withValues(alpha: 1), const Color(0xFF7C4DFF).withValues(alpha: 1)],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.white24, blurRadius: 3, spreadRadius: 0.5),
        ],
      ),
    );
  }
}

// FX model types
class _ArcParticle {
  final Offset start;
  final Offset control;
  final Offset end;
  final double t0;       // spawn time in seconds
  final double duration; // seconds
  final double size;     // logical px
  _ArcParticle({
    required this.start,
    required this.control,
    required this.end,
    required this.t0,
    required this.duration,
    required this.size,
  });
}

class _FloatText {
  final Offset start;
  final Offset end;
  final double t0;       // spawn time in seconds
  final double duration; // seconds
  final String text;
  _FloatText({
    required this.start,
    required this.end,
    required this.t0,
    required this.duration,
    required this.text,
  });
}
