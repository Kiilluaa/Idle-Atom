// lib/game/economy.dart
import 'dart:math';

/// Milestone multiplier used for both tap and rate:
/// +10% power every 25 owned
/// +15% power every 50 owned
/// ×2 power every 100 owned
double milestoneMult(int count) {
  final m25 = count ~/ 25;
  final m50 = count ~/ 50;
  final m100 = count ~/ 100;
  return (pow(1.10, m25) * pow(1.15, m50) * pow(2.0, m100)).toDouble();
}

/// Optional: stronger milestone bias for rate-only upgrades
double milestoneMultTyped(String type, int count) {
  final base = milestoneMult(count);
  if (type == 'rate' || type == 'ratex') {
    // small bias if you want rate to feel a touch stronger; tweak or remove
    return (base * 1.00).toDouble();
  }
  return base;
}

/// Current cost for the next purchase.
int upgradeCost(int base, int count, double defaultMult, [double? perMult]) {
  final m = perMult ?? defaultMult;
  return (base * pow(m, count)).floor();
}

/// Next N costs starting from current count (inclusive).
List<int> nextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
  final m = perMult ?? defaultMult;
  return List.generate(n, (k) => (base * pow(m, count + k)).floor());
}

/// Sum of the next N costs (buy N at once preview).
int sumNextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
  return nextCosts(base, count, defaultMult, n, perMult).fold(0, (a, b) => a + b);
}
