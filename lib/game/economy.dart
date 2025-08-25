// lib/game/economy.dart
import 'dart:math';

// Cost helpers
int upgradeCost(int base, int count, double defaultMult, [double? perMult]) {
  final m = perMult ?? defaultMult;
  return (base * pow(m, count)).floor();
}

List<int> nextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
  final m = perMult ?? defaultMult;
  final out = <int>[];
  for (int k = 0; k < n; k++) {
    out.add((base * pow(m, count + k)).floor());
  }
  return out;
}

int sumNextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
  return nextCosts(base, count, defaultMult, n, perMult).fold(0, (a, b) => a + b);
}

// Legacy milestone multiplier kept for compatibility
double milestoneMult(int count) {
  final m25 = count ~/ 25;
  final m50 = count ~/ 50;
  final m100 = count ~/ 100;
  return pow(1.10, m25) * pow(1.15, m50) * pow(2.0, m100).toDouble();
}

// New stepped value rule:
// 0–24: 1× base, 25–49: 2× base, 50–99: 3× base, 100–199: 4× base,
// then +1× base for each additional +100 (200, 300, 400, ...)
double valueStepMultiplier(int count) {
  int boosts = 0;
  if (count >= 25) boosts++;
  if (count >= 50) boosts++;
  if (count >= 100) boosts++;
  if (count > 100) boosts += (count - 100) ~/ 100;
  return 1.0 + boosts;
}

// Compute the next threshold at which the per-unit value steps up
int nextStepThreshold(int count) {
  if (count < 25) return 25;
  if (count < 50) return 50;
  if (count < 100) return 100;
  return ((count ~/ 100) + 1) * 100;
}