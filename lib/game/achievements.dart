// lib/game/achievements.dart
// Central place to define and check achievements. Keeps UI code clean.
// This mirrors your current categories/targets while being easy to test.

class Achievement {
  final String id;
  final String title;
  final String desc;
  final String category; // 'Currency' | 'Taps' | 'Upgrades' | 'Combo'
  final String metric;   // 'currency' | 'taps' | 'upgrades' | 'combo'
  final double? target;  // null for combo-style multi-conditions

  const Achievement({
    required this.id,
    required this.title,
    required this.desc,
    required this.category,
    required this.metric,
    this.target,
  });
}

class Achievements {
  // Same set you use today (you can tweak/extend here later).
  static const List<Achievement> all = [
    // Currency
    Achievement(id: 'cur_100',   title: 'Hundredaire',  desc: 'Earn 100 currency',     category: 'Currency', metric: 'currency', target: 100),
    Achievement(id: 'cur_1k',    title: 'Thousandaire', desc: 'Earn 1,000 currency',   category: 'Currency', metric: 'currency', target: 1000),
    Achievement(id: 'cur_10k',   title: 'Big Spender',  desc: 'Earn 10,000 currency',  category: 'Currency', metric: 'currency', target: 10000),
    Achievement(id: 'cur_100k',  title: 'Wealthy',      desc: 'Earn 100K currency',    category: 'Currency', metric: 'currency', target: 100000),
    Achievement(id: 'cur_1mil',  title: 'Millionaire',  desc: 'Earn 1M currency',      category: 'Currency', metric: 'currency', target: 1000000),
    Achievement(id: 'cur_10mil', title: 'Tycoon',       desc: 'Earn 10M currency',     category: 'Currency', metric: 'currency', target: 10000000),

    // Taps
    Achievement(id: 'tap_10',    title: 'Click Novice',     desc: 'Tap 10 times',        category: 'Taps', metric: 'taps', target: 10),
    Achievement(id: 'tap_100',   title: 'Click Apprentice', desc: 'Tap 100 times',       category: 'Taps', metric: 'taps', target: 100),
    Achievement(id: 'tap_1k',    title: 'Clicker Pro',      desc: 'Tap 1,000 times',     category: 'Taps', metric: 'taps', target: 1000),
    Achievement(id: 'tap_10k',   title: 'Click Legend',     desc: 'Tap 10,000 times',    category: 'Taps', metric: 'taps', target: 10000),
    Achievement(id: 'tap_100k',  title: 'Tap Machine',      desc: 'Tap 100,000 times',   category: 'Taps', metric: 'taps', target: 100000),
    Achievement(id: 'tap_1mil',  title: 'Tap God',          desc: 'Tap 1 million times', category: 'Taps', metric: 'taps', target: 1000000),

    // Upgrades
    Achievement(id: 'up_1',   title: 'Investor',     desc: 'Buy 1 upgrade',    category: 'Upgrades', metric: 'upgrades', target: 1),
    Achievement(id: 'up_10',  title: 'Manager',      desc: 'Buy 10 upgrades',  category: 'Upgrades', metric: 'upgrades', target: 10),
    Achievement(id: 'up_25',  title: 'Director',     desc: 'Buy 25 upgrades',  category: 'Upgrades', metric: 'upgrades', target: 25),
    Achievement(id: 'up_50',  title: 'Executive',    desc: 'Buy 50 upgrades',  category: 'Upgrades', metric: 'upgrades', target: 50),
    Achievement(id: 'up_100', title: 'Magnate',      desc: 'Buy 100 upgrades', category: 'Upgrades', metric: 'upgrades', target: 100),
    Achievement(id: 'up_250', title: 'Conglomerate', desc: 'Buy 250 upgrades', category: 'Upgrades', metric: 'upgrades', target: 250),

    // Combo (multi-conditions; targets checked in code)
    Achievement(id: 'combo_1', title: 'Getting Started',   desc: 'Tap 10 & Buy 1',                       category: 'Combo', metric: 'combo'),
    Achievement(id: 'combo_2', title: 'Small Business',    desc: 'Tap 100 & 1K Currency',                category: 'Combo', metric: 'combo'),
    Achievement(id: 'combo_3', title: 'Growing Fast',      desc: 'Tap 1K & 10 Upgrades',                 category: 'Combo', metric: 'combo'),
    Achievement(id: 'combo_4', title: 'Mid Tier Mogul',    desc: '5K Taps & 100K Currency',              category: 'Combo', metric: 'combo'),
    Achievement(id: 'combo_5', title: 'Corporate Climber', desc: '50 Upgrades & 1M Currency',            category: 'Combo', metric: 'combo'),
    Achievement(id: 'combo_6', title: 'Capitalist Elite',  desc: '100K Taps, 100 Upgrades, 10M Currency',category: 'Combo', metric: 'combo'),
  ];

  // Returns a set of **newly** unlocked achievement IDs (difference from alreadyUnlocked).
  static Set<String> check({
    required double totalCurrency,
    required int totalTaps,
    required int totalUpgrades,
    required Set<String> alreadyUnlocked,
  }) {
    final newly = <String>{};

    bool addIf(bool cond, String id) {
      if (cond && !alreadyUnlocked.contains(id)) {
        newly.add(id);
        return true;
      }
      return false;
    }

    for (final a in all) {
      if (alreadyUnlocked.contains(a.id)) continue;

      if (a.metric == 'currency' && a.target != null) {
        addIf(totalCurrency >= a.target!, a.id);
      } else if (a.metric == 'taps' && a.target != null) {
        addIf(totalTaps >= a.target!, a.id);
      } else if (a.metric == 'upgrades' && a.target != null) {
        addIf(totalUpgrades >= a.target!, a.id);
      } else if (a.metric == 'combo') {
        switch (a.id) {
          case 'combo_1': addIf(totalTaps >= 10 && totalUpgrades >= 1, a.id); break;
          case 'combo_2': addIf(totalTaps >= 100 && totalCurrency >= 1000, a.id); break;
          case 'combo_3': addIf(totalTaps >= 1000 && totalUpgrades >= 10, a.id); break;
          case 'combo_4': addIf(totalTaps >= 5000 && totalCurrency >= 100000, a.id); break;
          case 'combo_5': addIf(totalUpgrades >= 50 && totalCurrency >= 1000000, a.id); break;
          case 'combo_6': addIf(totalTaps >= 100000 && totalUpgrades >= 100 && totalCurrency >= 10000000, a.id); break;
        }
      }
    }
    return newly;
  }
}
