import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/scheduler.dart';
import 'atom_graphics.dart';

// ===================== FX TUNING KNOBS =====================
// Increase to make atoms travel farther sideways/upward.
const double kAtomDistanceMult = 1.0; // 1.0 = default
// Increase to make atoms complete their arc faster (shorter duration).
const double kAtomSpeedMult = 1;    // 1.0 = default
// Max simultaneous atoms and floating texts (oldest are dropped when capped).
const int kMaxArcParticles = 24;
const int kMaxFloatTexts  = 24;
// Text lifetime in seconds (how long the +X floats/fades).
const double kTextDuration = 1.0;
// Atom duration range (seconds) BEFORE speed multiplier is applied.
const double kAtomDurationMin = 0.70;
const double kAtomDurationMax = 1.00;
// Arc parameter ranges (pixels).
const double kLateralMin = 40;
const double kLateralMax = 90;
const double kRiseMin    = 80;
const double kRiseMax    = 140;
// Arc bow curvature factor (0..1).
const double kBowMin = 0.30;
const double kBowMax = 0.80;
// MiniAtom size range (logical px).
const double kMinAtomSize = 14;
const double kMaxAtomSize = 22;

// ===================== Floating FX layer =====================
class FloatingFxLayer extends StatefulWidget {
  const FloatingFxLayer({super.key});

  @override
  State<FloatingFxLayer> createState() => FloatingFxLayerState();
}

class FloatingFxLayerState extends State<FloatingFxLayer>
    with SingleTickerProviderStateMixin {
  Ticker? _fxTicker;
  double _fxTime = 0.0; // seconds

  final Random _rng = Random();
  final List<_ArcParticle> _arc = [];
  final List<_FloatText> _texts = [];

  @override
  void initState() {
    super.initState();
    _fxTicker ??= createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _fxTime = elapsed.inMicroseconds / 1e6;
        _arc.removeWhere((p) => _fxTime - p.t0 >= p.duration);
        _texts.removeWhere((t) => _fxTime - t.t0 >= t.duration);
      });
    })..start();
  }

  @override
  void dispose() {
    _fxTicker?.dispose();
    super.dispose();
  }

  /// Spawn a MiniAtom that travels along a bowed quadratic arc in a random
  /// left/right direction, and a plain "+X" label that rises and fades out.
  void spawnTapFx(Offset localPos, String text) {
    final now = _fxTime;

    final dirRight = _rng.nextBool() ? 1.0 : -1.0;
    final lateral = lerpDouble(kLateralMin, kLateralMax, _rng.nextDouble())! * kAtomDistanceMult;
    final rise    = lerpDouble(kRiseMin,    kRiseMax,    _rng.nextDouble())! * kAtomDistanceMult;
    final rawDur  = lerpDouble(kAtomDurationMin, kAtomDurationMax, _rng.nextDouble())!;
    final dur     = (rawDur / kAtomSpeedMult).clamp(0.15, 5.0);
    final size    = lerpDouble(kMinAtomSize, kMaxAtomSize, _rng.nextDouble())!;
    final bow     = lerpDouble(kBowMin, kBowMax, _rng.nextDouble())!;

    // Cap lists to avoid unbounded growth when spam-tapping
    while (_arc.length >= kMaxArcParticles) {_arc.removeAt(0);}
    while (_texts.length >= kMaxFloatTexts) {_texts.removeAt(0);}

    _arc.add(
      _ArcParticle(
        start: localPos,
        control: localPos + Offset(dirRight * lateral * 0.5, -rise * bow),
        end: localPos + Offset(dirRight * lateral, -rise),
        t0: now,
        duration: dur,
        size: size,
      ),
    );

    _texts.add(
      _FloatText(
        start: localPos + const Offset(0, -8),
        end: localPos + const Offset(0, -90),
        t0: now,
        duration: kTextDuration,
        text: text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          for (final p in _arc) _ArcWidget(p: p, time: _fxTime),
          for (final ft in _texts) _FloatTextWidget(t: ft, time: _fxTime),
        ],
      ),
    );
  }
}

// ---- Widgets / Models ----

class _ArcParticle {
  final Offset start;
  final Offset control;
  final Offset end;
  final double t0;       // spawn time (seconds)
  final double duration; // seconds
  final double size;     // MiniAtom size
  _ArcParticle({
    required this.start,
    required this.control,
    required this.end,
    required this.t0,
    required this.duration,
    required this.size,
  });
}

class _ArcWidget extends StatelessWidget {
  const _ArcWidget({required this.p, required this.time});
  final _ArcParticle p;
  final double time;

  @override
  Widget build(BuildContext context) {
    double t = ((time - p.t0) / p.duration).clamp(0.0, 1.0);

    Offset lerpQ(Offset a, Offset b, double t) =>
        Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    final q1 = lerpQ(p.start, p.control, t);
    final q2 = lerpQ(p.control, p.end, t);
    final pos = lerpQ(q1, q2, t);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Transform.translate(
        offset: Offset(-p.size / 2, -p.size / 2),
        child: MiniAtom(size: p.size),
      ),
    );
  }
}

class _FloatText {
  final Offset start;
  final Offset end;
  final double t0;
  final double duration;
  final String text;
  _FloatText({
    required this.start,
    required this.end,
    required this.t0,
    required this.duration,
    required this.text,
  });
}

class _FloatTextWidget extends StatelessWidget {
  const _FloatTextWidget({required this.t, required this.time});
  final _FloatText t;
  final double time;

  @override
  Widget build(BuildContext context) {
    final p = ((time - t.t0) / t.duration).clamp(0.0, 1.0);
    final x = lerpDouble(t.start.dx, t.end.dx, p)!;
    final y = lerpDouble(t.start.dy, t.end.dy, p)!;
    final opacity = (1.0 - p).clamp(0.0, 1.0);

    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: const Offset(-8, -8),
          child: Text(
            t.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(blurRadius: 6, color: Colors.black, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}
