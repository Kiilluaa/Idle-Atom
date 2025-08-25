// lib/game/game_state.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'upgrades.dart';
import 'achievements.dart';

class GameState extends ChangeNotifier {
  GameState({required List<Upgrade> initialUpgrades})
      : upgrades = initialUpgrades;

  // ========= Settings / options =========
  int backgroundStyle = 0;
  bool haptics = true;
  bool reduceAnimations = false;

  // ========= Core counters =========
  double counter = 0;            // currency on hand (wallet)
  double tapValue = 1.0;         // base tap value (unboosted)
  double passiveRate = 0.0;      // base passive income per second

  // Totals for achievements / stats (persisted)
  int totalTaps = 0;
  int totalUpgrades = 0;
  double totalCurrencyEarned = 0; // cumulative earned (for "Earn X" achievements)

  // Achievements (IDs). UI reads this directly.
  final Set<String> unlocked = <String>{};

  // Upgrades provided by createDefaultUpgrades()
  final List<Upgrade> upgrades;

  // ========= Persistence meta (used by UI toast) =========
  int saveVersion = 0;       // bump each save so UI can notice
  bool lastSaveWasAuto = false;

  // ========= Achievement unlock event for UI popups =========
  int unlockVersion = 0;     // increment when a new achievement unlocks
  String? lastUnlockedId;    // id of the most recently unlocked achievement

  // ========= Tickers =========
  Timer? _ticker;            // game ticker (passive income + UI refresh)
  Timer? _autosaveTimer;     // autosave every 2 minutes

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      // Passive income tick (1/4 second) — use BOOSTED rate
      if (currentPassiveRate != 0) {
        final add = currentPassiveRate / 4.0;
        counter += add;
        totalCurrencyEarned += add;
        _checkForAchievements();
      }
      // Keep UI responsive (buff overlay countdown, etc.)
      notifyListeners();
    });
  }

  void _ensureAutosave() {
    _autosaveTimer ??= Timer.periodic(const Duration(minutes: 2), (_) async {
      lastSaveWasAuto = true;
      await save(silent: true);
      lastSaveWasAuto = false;
    });
  }

  // ========= BOOST (×10 with +15s extensions) =========
  bool isBuffActive = false;
  int? _buffEndEpochMs;   // hard deadline (ms since epoch)
  int _buffTotalMs = 0;   // denominator for overlay/progress

  // UI getters (read-only)
  int get buffTotalMs => _buffTotalMs;
  int get buffRemainingMs {
    if (!isBuffActive || _buffEndEpochMs == null) {
      return 0;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = _buffEndEpochMs! - now;
    return remaining.clamp(0, _buffTotalMs);
  }

  // Boosted effective values (used by UI & ticker)
  double get currentTapValue => isBuffActive ? tapValue * 10.0 : tapValue;
  double get currentPassiveRate => isBuffActive ? passiveRate * 10.0 : passiveRate;

  Timer? _buffTicker;
  void _ensureBuffTicker() {
    if (_buffTicker != null) {
      return;
    }
    _buffTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!isBuffActive || _buffEndEpochMs == null) {
        _buffTicker?.cancel();
        _buffTicker = null;
        return;
      }
      if (now >= _buffEndEpochMs!) {
        // Expire
        isBuffActive = false;
        _buffEndEpochMs = null;
        _buffTotalMs = 0;
        notifyListeners();
        return;
      }
      // Still active -> refresh overlay countdown
      notifyListeners();
    });
  }

  /// Start a 15s boost or extend current boost by +15s (no stacking multipliers).
  void startOrExtendBoost({int addMs = 15000}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isBuffActive && _buffEndEpochMs != null) {
      _buffEndEpochMs = _buffEndEpochMs! + addMs;
      _buffTotalMs += addMs;
    } else {
      isBuffActive = true;
      _buffEndEpochMs = now + addMs;
      _buffTotalMs = addMs;
      _ensureBuffTicker();
    }
    notifyListeners();
  }

  /// Optional helper to force-end the boost (handy for testing).
  void endBoostNow() {
    if (!isBuffActive) {
      return;
    }
    isBuffActive = false;
    _buffEndEpochMs = null;
    _buffTotalMs = 0;
    notifyListeners();
  }

  /// Mark an achievement ID as unlocked (idempotent) and (optionally) grant boost.
  void markAchievementUnlocked(String id, {bool grantBoost = true}) {
    if (unlocked.contains(id)) {
      return;
    }
    unlocked.add(id);

    // Emit unlock event for UI popup
    lastUnlockedId = id;
    unlockVersion++;

    if (grantBoost) {
      startOrExtendBoost(addMs: 15000);
    }
    notifyListeners();
  }

  // ========= Achievements integration =========
  void _checkForAchievements() {
    final newly = Achievements.check(
      totalCurrency: totalCurrencyEarned, // change to counter if you prefer wallet-based
      totalTaps: totalTaps,
      totalUpgrades: totalUpgrades,
      alreadyUnlocked: unlocked,
    );
    if (newly.isEmpty) {
      return;
    }
    for (final id in newly) {
      markAchievementUnlocked(id);
    }
  }

  // ========= Upgrade pricing & purchase =========
  // Coerce possibly-null/num fields to double safely
  double _asDouble(num? n, {double ifNull = 0.0}) {
    return (n == null) ? ifNull : n.toDouble();
  }

  // Geometric total price for next [qty] units starting from current count.
  // Assumes Upgrade has: num? baseCost, num? costMult, int count.
  double _totalCostFor(Upgrade u, int qty) {
    final double baseCost = _asDouble(u.baseCost, ifNull: 0.0);
    final double r = _asDouble(u.costMult, ifNull: 1.0);
    final int start = u.count;
    if (qty <= 0) {
      return 0;
    }

    // Sum_{k=0..qty-1} baseCost * r^(start + k)
    if (r == 1.0) {
      return baseCost * qty;
    } else {
      // baseCost * r^start * (r^qty - 1) / (r - 1)
      final double rStart = pow(r, start).toDouble();
      final double rQty = pow(r, qty).toDouble();
      return baseCost * rStart * (rQty - 1.0) / (r - 1.0);
    }
  }

  /// Buy [qty] of upgrade at [index]. Handles affordability, deduction, counts, recompute, achievements.
  bool buyUpgrade(int index, int qty) {
    if (index < 0 || index >= upgrades.length || qty <= 0) {
      return false;
    }
    final u = upgrades[index];

    final double cost = _totalCostFor(u, qty);
    if (cost <= 0) {
      return false;
    }
    if (counter + 1e-9 < cost) {
      return false;
    }

    counter -= cost;
    u.count += qty;
    totalUpgrades += qty;

    recomputeStats();
    _checkForAchievements();

    notifyListeners();
    return true;
  }

  // ========= Flexible classification for upgrades =========

  String _norm(String? s) {
    return (s ?? '').toLowerCase().trim();
  }

  bool _containsAny(String hay, List<String> needles) {
    for (final n in needles) {
      if (hay.contains(n)) {
        return true;
      }
    }
    return false;
  }

  /// Returns 'tap', 'passive', or 'unknown' using type first, then label as fallback.
  String _classifyUpgrade(Upgrade u) {
    final t = _norm(u.type);
    final lbl = _norm(u.label);

    // Primary: type substring match (common variants)
    if (_containsAny(t, [
      'tap', 'click', 'per_tap', 'pertap', 'perclick', 'tpc', 'tapmult', 'tap-mult', 'tap_mult'
    ])) {
      return 'tap';
    }

    if (_containsAny(t, [
      'passive', 'rate', 'per_sec', 'persec', 'rps', 'pps', 'income', 'passiverate', 'passive_rate'
    ])) {
      return 'passive';
    }

    // Fallback: infer from label (e.g., "Quantum Tuner")
    if (_containsAny(lbl, [
      'tap', 'click', 'per tap', 'per-click', 'click power', 'quantum tuner', 'tuner'
    ])) {
      return 'tap';
    }

    if (_containsAny(lbl, [
      'rate', 'per sec', 'income', 'rps'
    ])) {
      return 'passive';
    }

    return 'unknown';
  }

  /// Recompute base tapValue & passiveRate from upgrades.
  /// - Accepts many synonymous type strings; falls back to label inference.
  /// - Handles nullable numbers via _asDouble.
  /// - Additive then multiplicative stacking per-upgrade.
  void recomputeStats() {
    double baseTap = 1.0;
    double basePassive = 0.0;

    for (final u in upgrades) {
      final int count = u.count;
      if (count <= 0) {
        continue;
      }

      final double val  = _asDouble(u.value, ifNull: 0.0);
      final double mult = _asDouble(u.mult,  ifNull: 1.0);

      switch (_classifyUpgrade(u)) {
        case 'tap': {
          baseTap += val * count;
          baseTap *= pow(mult, count).toDouble();
          break;
        }
        case 'passive': {
          basePassive += val * count;
          basePassive *= pow(mult, count).toDouble();
          break;
        }
        case 'unknown': {
          // ignore silently
          break;
        }
      }
    }

    if (baseTap.isNaN || baseTap.isInfinite) {
      baseTap = 1.0;
    }
    if (basePassive.isNaN || basePassive.isInfinite) {
      basePassive = 0.0;
    }

    tapValue = baseTap;
    passiveRate = basePassive;
  }

  // ========= Lifecycle: load/save/dispose =========

  // Safely read a number that might have been saved as double or int in the past.
  double _readDouble(SharedPreferences prefs, String key, double fallback) {
    final Object? v = prefs.get(key);
    if (v is double) {
      return v;
    }
    if (v is int) {
      return v.toDouble();
    }
    return fallback;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    backgroundStyle = prefs.getInt('backgroundStyle') ?? backgroundStyle;
    haptics = prefs.getBool('haptics') ?? haptics;
    reduceAnimations = prefs.getBool('reduceAnimations') ?? reduceAnimations;

    counter = _readDouble(prefs, 'counter', counter);
    tapValue = _readDouble(prefs, 'tapValue', tapValue);
    passiveRate = _readDouble(prefs, 'passiveRate', passiveRate);

    totalTaps = prefs.getInt('totalTaps') ?? totalTaps;
    totalUpgrades = prefs.getInt('totalUpgrades') ?? totalUpgrades;
    totalCurrencyEarned = _readDouble(prefs, 'totalCurrencyEarned', totalCurrencyEarned);

    // Achievements
    final unlockedList = prefs.getStringList('unlocked') ?? const <String>[];
    unlocked
      ..clear()
      ..addAll(unlockedList);

    // Upgrades counts (by index)
    final upgradeCounts = prefs.getStringList('upgradeCounts');
    if (upgradeCounts != null && upgradeCounts.length == upgrades.length) {
      for (int i = 0; i < upgrades.length; i++) {
        final v = int.tryParse(upgradeCounts[i]) ?? 0;
        upgrades[i].count = v;
      }
      // Recompute from upgrades
      recomputeStats();
    }

    // Boost
    isBuffActive = prefs.getBool('isBuffActive') ?? false;
    final Object? endRaw = prefs.get('buffEndEpochMs');
    final Object? totRaw = prefs.get('buffTotalMs');
    _buffEndEpochMs = (endRaw is int) ? endRaw : null;
    _buffTotalMs = (totRaw is int) ? totRaw : 0;

    // If expired while we were away, clear it; else resume ticker.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_buffEndEpochMs == null || now >= _buffEndEpochMs!) {
      isBuffActive = false;
      _buffEndEpochMs = null;
      _buffTotalMs = 0;
    } else {
      _ensureBuffTicker();
    }

    _ensureTicker();
    _ensureAutosave();
    notifyListeners();
  }

  Future<void> save({bool silent = false}) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('backgroundStyle', backgroundStyle);
    await prefs.setBool('haptics', haptics);
    await prefs.setBool('reduceAnimations', reduceAnimations);

    await prefs.setDouble('counter', counter);
    await prefs.setDouble('tapValue', tapValue);
    await prefs.setDouble('passiveRate', passiveRate);

    await prefs.setInt('totalTaps', totalTaps);
    await prefs.setInt('totalUpgrades', totalUpgrades);
    await prefs.setDouble('totalCurrencyEarned', totalCurrencyEarned);

    await prefs.setStringList('unlocked', unlocked.toList());

    // Upgrades counts (by index)
    await prefs.setStringList(
      'upgradeCounts',
      upgrades.map((u) => u.count.toString()).toList(),
    );

    // Boost
    await prefs.setBool('isBuffActive', isBuffActive);
    if (_buffEndEpochMs != null) {
      await prefs.setInt('buffEndEpochMs', _buffEndEpochMs!);
    } else {
      await prefs.remove('buffEndEpochMs');
    }
    await prefs.setInt('buffTotalMs', _buffTotalMs);

    // For UI toast logic
    saveVersion++;
    if (!silent) {
      lastSaveWasAuto = false;
      notifyListeners();
    } else {
      // still notify so version change is observed
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autosaveTimer?.cancel();
    _buffTicker?.cancel();
    super.dispose();
  }

  // ========= Public API called by UI =========
  void handleTap() {
    final add = currentTapValue; // boosted tap value
    counter += add;
    totalCurrencyEarned += add;
    totalTaps += 1;

    _checkForAchievements();
    notifyListeners();
  }
}