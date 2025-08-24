// lib/widgets/spectrometer_strip.dart
import 'dart:ui';
import 'package:flutter/material.dart';

/// Curved, glassy bottom strip used to display currency (and optionally stats).
class SpectrometerStrip extends StatelessWidget {
  const SpectrometerStrip({
    super.key,
    required this.width,
    required this.height,
    required this.currency,
    required this.ratePerSec,
    required this.tapValue,
  });

  final double width;
  final double height;
  final String currency;
  final String ratePerSec;
  final String tapValue;

  @override
  Widget build(BuildContext context) {
    final onlyCurrency = ratePerSec.isEmpty && tapValue.isEmpty;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(width, height),
            painter: _SpectrometerStrokePainter(),
          ),
          ClipPath(
            clipper: _SpectrometerClipper(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color.fromRGBO(255, 255, 255, 0.08),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: onlyCurrency ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: onlyCurrency
                      ? [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                currency,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ]
                      : [
                          _StatCell(icon: Icons.account_balance_wallet, label: 'Currency', value: currency),
                          const _DividerDot(),
                          _StatCell(icon: Icons.speed, label: 'Rate', value: ratePerSec),
                          const _DividerDot(),
                          _StatCell(icon: Icons.touch_app, label: 'Tap', value: tapValue),
                        ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerDot extends StatelessWidget {
  const _DividerDot();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _SpectrometerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _spectrometerPath(size);
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;

  Path _spectrometerPath(Size size) {
    final w = size.width;
    final h = size.height;
    final arc = h * 0.9;

    final path = Path();
    path.moveTo(0, arc);
    path.quadraticBezierTo(w / 2, -arc * 0.7, w, arc);
    path.lineTo(w, h - 2);
    path.quadraticBezierTo(w / 2, h + arc * 0.6, 0, h - 2);
    path.close();
    return path;
  }
}

class _SpectrometerStrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _SpectrometerClipper()._spectrometerPath(size);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shader = const LinearGradient(
      colors: [Color(0x55B388FF), Color(0x5596E6F6), Color(0x557C4DFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..shader = shader
      ..strokeWidth = 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
