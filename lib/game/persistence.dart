// lib/game/persistence.dart
import 'package:shared_preferences/shared_preferences.dart';

// Simple persistence helpers that decouple storage from your UI.
// You can keep using your current state shape and call these helpers
// to load/save a snapshot map.
class Persistence {
  // Keys
  static const _kCounter = 'counter';
  static const _kTapValue = 'tapValue';
  static const _kPassiveRate = 'passiveRate'; // kept for compatibility, but you recompute
  static const _kTotalTaps = 'totalTaps';
  static const _kTotalUpgrades = 'totalUpgrades';
  static const _kTotalCurrency = 'totalCurrencyEarned';

  static const _kUnlocked = 'unlockedAchievements';
  static const _kHaptics = 'haptics';
  static const _kReduceAnims = 'reduceAnimations';
  static const _kBackgroundStyle = 'backgroundStyle';

  static const _kLastSavedMillis = 'lastSavedMillis';
  static String _kUpgradeCount(int i) => 'upgrade_count_$i';

  // Loads a snapshot. You must pass [numUpgrades] so counts can be read back.
  // Returns a map with the same field names you already use.
  static Future<Map<String, dynamic>> load({required int numUpgrades}) async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};

    map['counter'] = prefs.getDouble(_kCounter) ?? 0.0;
    map['tapValue'] = prefs.getDouble(_kTapValue) ?? 1.0;
    map['passiveRate'] = prefs.getDouble(_kPassiveRate) ?? 0.0; // will be recomputed
    map['totalTaps'] = prefs.getInt(_kTotalTaps) ?? 0;
    map['totalUpgrades'] = prefs.getInt(_kTotalUpgrades) ?? 0;
    map['totalCurrencyEarned'] = prefs.getDouble(_kTotalCurrency) ?? 0.0;

    map['unlockedAchievements'] = prefs.getStringList(_kUnlocked) ?? <String>[];
    map['haptics'] = prefs.getBool(_kHaptics) ?? true;
    map['reduceAnimations'] = prefs.getBool(_kReduceAnims) ?? false;
    map['backgroundStyle'] = prefs.getInt(_kBackgroundStyle) ?? 0;

    map['lastSavedMillis'] = prefs.getInt(_kLastSavedMillis);

    // Upgrade counts
    final counts = <int>[];
    for (int i = 0; i < numUpgrades; i++) {
      counts.add(prefs.getInt(_kUpgradeCount(i)) ?? 0);
    }
    map['upgradeCounts'] = counts;

    return map;
  }

  // Saves a snapshot. Provide [upgradeCounts] matching your upgrades list length.
  static Future<void> save({
    required double counter,
    required double tapValue,
    required double passiveRate,
    required int totalTaps,
    required int totalUpgrades,
    required double totalCurrencyEarned,
    required List<String> unlockedAchievements,
    required bool haptics,
    required bool reduceAnimations,
    required int backgroundStyle,
    required List<int> upgradeCounts,
    required int nowMillis,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(_kCounter, counter);
    await prefs.setDouble(_kTapValue, tapValue);
    await prefs.setDouble(_kPassiveRate, passiveRate); // kept for compatibility
    await prefs.setInt(_kTotalTaps, totalTaps);
    await prefs.setInt(_kTotalUpgrades, totalUpgrades);
    await prefs.setDouble(_kTotalCurrency, totalCurrencyEarned);
    await prefs.setStringList(_kUnlocked, unlockedAchievements);
    await prefs.setBool(_kHaptics, haptics);
    await prefs.setBool(_kReduceAnims, reduceAnimations);
    await prefs.setInt(_kBackgroundStyle, backgroundStyle);

    for (int i = 0; i < upgradeCounts.length; i++) {
      await prefs.setInt(_kUpgradeCount(i), upgradeCounts[i]);
    }

    await prefs.setInt(_kLastSavedMillis, nowMillis);
  }

  // Helper to clear all saved data (same as your reset button).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
