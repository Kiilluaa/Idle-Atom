import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game/economy.dart';
import '../game/persistence.dart';
import '../game/achievements.dart';
import 'upgrades.dart';

/// Central game logic container. Keeps Widgets thin.
class GameState extends ChangeNotifier {
  // Core numbers
  double counter = 0;
  double passiveRate = 0;
  double tapValue = 1.0;
  double totalCurrencyEarned = 0;
  int totalTaps = 0;
  int totalUpgrades = 0;

  // Settings
  bool haptics = true;
  bool reduceAnimations = false;
  int backgroundStyle = 0;

  // Achievements
  final Set<String> unlocked = {};

  // Upgrades
  final List<Upgrade> upgrades;

  // Timers
  Timer? _passiveTimer;
  Timer? _autoSaveTimer;

  // Persistence helpers
  int? _lastSavedMillis;
  DateTime? _lastSaveToastAt;

  GameState({List<Upgrade>? initialUpgrades})
      : upgrades = (initialUpgrades ?? createDefaultUpgrades())
            .map((u) => u.copyWith(count: 0)).toList();

  // --- Lifecycle ---
  Future<void> load() async {
    final snap = await Persistence.load(numUpgrades: upgrades.length);
    counter               = (snap['counter'] as num?)?.toDouble() ?? 0.0;
    tapValue              = (snap['tapValue'] as num?)?.toDouble() ?? 1.0;
    passiveRate           = (snap['passiveRate'] as num?)?.toDouble() ?? 0.0;
    totalTaps             = snap['totalTaps'] as int? ?? 0;
    totalUpgrades         = snap['totalUpgrades'] as int? ?? 0;
    totalCurrencyEarned   = (snap['totalCurrencyEarned'] as num?)?.toDouble() ?? 0.0;
    haptics               = snap['haptics'] as bool? ?? true;
    reduceAnimations      = snap['reduceAnimations'] as bool? ?? false;
    backgroundStyle       = snap['backgroundStyle'] as int? ?? 0;
    _lastSavedMillis      = snap['lastSavedMillis'] as int?;

    final unlockedList = (snap['unlockedAchievements'] as List).cast<String>();
    unlocked
      ..clear()
      ..addAll(unlockedList);

    // restore upgrade counts
    final counts = (snap['upgradeCounts'] as List).cast<int>();
    for (int i = 0; i < upgrades.length; i++) {
      upgrades[i].count = counts[i];
    }

    recomputeStats();
    _applyIdleRewardsIfAny();
    await save(silent: true);
    startTimers();
    _checkAchievements();
    notifyListeners();
  }

  Future<void> save({bool silent = false}) async {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final upgradeCounts = upgrades.map((u) => u.count).toList();

    await Persistence.save(
      counter: counter,
      tapValue: tapValue,
      passiveRate: passiveRate,
      totalTaps: totalTaps,
      totalUpgrades: totalUpgrades,
      totalCurrencyEarned: totalCurrencyEarned,
      unlockedAchievements: unlocked.toList(),
      haptics: haptics,
      reduceAnimations: reduceAnimations,
      backgroundStyle: backgroundStyle,
      upgradeCounts: upgradeCounts,
      nowMillis: nowMillis,
    );
    _lastSavedMillis = nowMillis;

    if (!silent) {
      final now = DateTime.now();
      if (_lastSaveToastAt == null ||
          now.difference(_lastSaveToastAt!) >= const Duration(seconds: 3)) {
        _lastSaveToastAt = now;
        // UI layer should show a snackbar; we can't from here.
      }
    }
  }

  void startTimers() {
    _passiveTimer?.cancel();
    _autoSaveTimer?.cancel();

    _passiveTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final earned = passiveRate * 0.25;
      counter += earned;
      totalCurrencyEarned += earned;
      _checkAchievements();
      notifyListeners();
    });

    _autoSaveTimer =
        Timer.periodic(const Duration(minutes: 2), (_) => save(silent: true));
  }

  @override
  void dispose() {
    _passiveTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  // --- Actions ---
  void handleTap({bool doHaptics = false}) {
    counter += tapValue;
    totalTaps++;
    totalCurrencyEarned += tapValue;
    if (doHaptics) {
      HapticFeedback.selectionClick();
    }
    _checkAchievements();
    notifyListeners();
  }

  void buyUpgrade(int index, int qty) {
    if (index < 0 || index >= upgrades.length) return;
    final u = upgrades[index];
    upgrades[index] = u.copyWith(count: u.count + qty);
    totalUpgrades += qty;
    recomputeStats();
    _checkAchievements();
    notifyListeners();
  }

  // --- Stats ---
  void recomputeStats() {
    double rate = 0.0;
    double tapBase = 1.0;
    double tapFlat = 0.0;
    double tapMult = 1.0;
    double rateMult = 1.0;

    for (final u in upgrades) {
      final int c = u.count;
      if (c == 0) continue;
      final double milestone = milestoneMult(c);

      if (u.type == 'rate') {
        rate += c * (u.value ?? 0) * milestone;
      } else if (u.type == 'tap') {
        tapFlat += c * (u.value ?? 0) * milestone;
      } else if (u.type == 'tapx') {
        final double m = (u.mult ?? 1.10);
        tapMult *= pow(m, c) * milestone;
      } else if (u.type == 'ratex') {
        final double m = (u.mult ?? 1.10);
        rateMult *= pow(m, c) * milestone;
      }
    }

    passiveRate = rate * rateMult;
    tapValue = (tapBase + tapFlat) * tapMult;
  }

  // --- Helpers ---
  void _applyIdleRewardsIfAny() {
    if (_lastSavedMillis == null) return;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final elapsedSec = max(0, (nowMillis - _lastSavedMillis!) ~/ 1000);
    if (elapsedSec <= 0 || passiveRate <= 0) return;

    const capHours = 12;
    final cappedSec = min(elapsedSec, capHours * 3600);
    final gained = passiveRate * cappedSec;
    counter += gained;
    totalCurrencyEarned += gained;
  }

  void _checkAchievements() {
    final newly = Achievements.check(
      totalCurrency: totalCurrencyEarned,
      totalTaps: totalTaps,
      totalUpgrades: totalUpgrades,
      alreadyUnlocked: unlocked,
    );
    if (newly.isEmpty) return;
    unlocked.addAll(newly);
  }

  // Utility used by UI (same math as before)
  int getCurrentCost(int base, int count, double defaultMult, [double? perMult]) {
    final m = perMult ?? defaultMult;
    return (base * (pow(m, count))).floor();
  }
}