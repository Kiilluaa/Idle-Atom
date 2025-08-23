
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

// ===================== APP ROOT (Stateless) =====================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clicker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: const MyHomePage(),
    );
  }
}

// ===================== HOME PAGE =====================
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  double _counter = 0;
  double _passiveRate = 0;
  double _tapValue = 1.0;
  double _totalCurrencyEarned = 0;
  int _totalTaps = 0;
  int _totalUpgrades = 0;
  bool _isExpanded = false;
  double _tapScale = 1.0;
  final Duration _tapAnimDuration = const Duration(milliseconds: 100);

  Timer? _passiveTimer;
  Timer? _autoSaveTimer;

  // Default/global cost multiplier (per-upgrade overrides may exist)
  final double _defaultCostMultiplier = 1.15;

  final Set<String> _unlocked = {};
  final List<Map<String, dynamic>> _achievements = [];
  final Map<String, List<Map<String, dynamic>>> _grouped = {
    'Currency': [],
    'Taps': [],
    'Upgrades': [],
    'Combo': [],
  };

  // Settings (kept local; persisted via SharedPreferences)
  bool _haptics = true;
  bool _reduceAnimations = false;
  // 0 = Indigo/Blue, 1 = Graphite, 2 = Teal/Navy
  int _backgroundStyle = 0;

  // Idle rewards timestamp
  int? _lastSavedMillis;

  // Save throttling (UI toast)
  DateTime? _lastSaveToastAt;

  // ======== Upgrades (science/atom theme) ========
  // Cookie-style: allow per-upgrade costMult and multiplicative 'tapx' upgrades.
  final List<Map<String, dynamic>> _upgrades = [
    {'label': 'Ion Trap',        'color': Colors.teal,    'baseCost': 50,      'value': 0.1, 'count': 0, 'type': 'rate', 'costMult': 1.13},
    {'label': 'Fusion Chamber',  'color': Colors.orange,  'baseCost': 225,     'value': 0.2, 'count': 0, 'type': 'rate', 'costMult': 1.14},
    // multiplicative tap upgrade
    {'label': 'Quantum Tuner',   'color': Colors.green,   'baseCost': 950,     'mult': 1.15, 'count': 0, 'type': 'tapx', 'costMult': 1.14},
    {'label': 'Muon Gauntlet',   'color': Colors.red,     'baseCost': 4000,    'value': 2.0, 'count': 0, 'type': 'tap',  'costMult': 1.15},
    {'label': 'Research Grant',  'color': Colors.blue,    'baseCost': 17000,   'value': 1.0, 'count': 0, 'type': 'rate', 'costMult': 1.15},
    {'label': 'Nanobot Swarm',   'color': Colors.pink,    'baseCost': 70000,   'value': 3.0, 'count': 0, 'type': 'tap',  'costMult': 1.16},
    {'label': 'Dyson Swarm',     'color': Colors.cyan,    'baseCost': 300000,  'value': 5.0, 'count': 0, 'type': 'rate', 'costMult': 1.16},
    // optional late-game multiplicative tap
    {'label': 'Quantum Overclock','color': Colors.purple, 'baseCost': 1200000, 'mult': 1.25, 'count': 0, 'type': 'tapx', 'costMult': 1.16},
  ];

  // ======== FX layer control ========
  final GlobalKey<FloatingFxLayerState> _fxKey = GlobalKey<FloatingFxLayerState>();
  final GlobalKey _stackKey = GlobalKey();

  // === Helpers ===

  // Compact formatter:
  // < 1000 => whole number only; >=1000 => K/M/B with 0–2 decimals, stripped trailing .0/.00
  String _fmtCompact(num v) {
    final sign = v < 0 ? '-' : '';
    double n = v.abs().toDouble();
    const units = ['', 'K', 'M', 'B', 'T', 'P', 'E'];
    int i = 0;
    while (n >= 1000 && i < units.length - 1) {
      n /= 1000;
      i++;
    }
    String s;
    if (i == 0) {
      s = n.toStringAsFixed(0);
    } else {
      if (n >= 100) {
        s = n.toStringAsFixed(0);
      } else if (n >= 10) {
        s = n.toStringAsFixed(1);
      } else {
        s = n.toStringAsFixed(2);
      }
      s = s.replaceAll(RegExp(r'\.?0+$'), '');
    }
    return '$sign$s${units[i]}';
  }

  double _clampDouble(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  // Cookie-style milestones: +10% per 25, +15% per 50, ×2 per 100
  double _milestoneMult(int count) {
    final m25 = count ~/ 25;
    final m50 = count ~/ 50;
    final m100 = count ~/ 100;
    return pow(1.10, m25) * pow(1.15, m50) * pow(2.0, m100).toDouble();
  }

  // Recompute tap/passive stats from counts every time
  void _recomputeStats() {
    double rate = 0.0;
    double tapBase = 1.0;   // base tap
    double tapFlat = 0.0;   // additive
    double tapMult = 1.0;   // multiplicative

    for (final u in _upgrades) {
      final int c = (u['count'] as int);
      if (c == 0) continue;
      final String t = u['type'] as String;
      final double milestone = _milestoneMult(c);

      if (t == 'rate') {
        rate += c * (u['value'] as double) * milestone;
      } else if (t == 'tap') {
        tapFlat += c * (u['value'] as double) * milestone;
      } else if (t == 'tapx') {
        final double m = (u['mult'] as double? ?? 1.10);
        tapMult *= pow(m, c) * milestone;
      }
    }

    setState(() {
      _passiveRate = rate;
      _tapValue = (tapBase + tapFlat) * tapMult;
    });
  }

  int getCurrentCost(int base, int count, double defaultMult, [double? perMult]) {
    final m = perMult ?? defaultMult;
    return (base * pow(m, count)).floor();
  }

  List<int> nextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
    final m = perMult ?? defaultMult;
    final costs = <int>[];
    for (int k = 0; k < n; k++) {
      costs.add((base * pow(m, count + k)).floor());
    }
    return costs;
  }

  int sumNextCosts(int base, int count, double defaultMult, int n, [double? perMult]) {
    return nextCosts(base, count, defaultMult, n, perMult).fold(0, (a, b) => a + b);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAchievements();
    _loadData().then((_) {
      // Recompute BEFORE idle rewards so passive uses latest math
      _recomputeStats();
      _applyIdleRewardsIfAny(); // grant offline earnings on startup (capped)
      _saveData(silent: true);
      _startTimer();
      _autoSaveTimer = Timer.periodic(const Duration(minutes: 2), (_) => _saveData(silent: true));
      _checkAchievements();
    });
  }

  void _initializeAchievements() {
    final List<Map<String, dynamic>> all = [
      // Currency
      {'id': 'cur_100',   'title': 'Hundredaire',   'desc': 'Earn 100 currency',     'category': 'Currency', 'target': 100,      'metric': 'currency'},
      {'id': 'cur_1k',    'title': 'Thousandaire',  'desc': 'Earn 1,000 currency',   'category': 'Currency', 'target': 1000,     'metric': 'currency'},
      {'id': 'cur_10k',   'title': 'Big Spender',   'desc': 'Earn 10,000 currency',  'category': 'Currency', 'target': 10000,    'metric': 'currency'},
      {'id': 'cur_100k',  'title': 'Wealthy',       'desc': 'Earn 100K currency',    'category': 'Currency', 'target': 100000,   'metric': 'currency'},
      {'id': 'cur_1mil',  'title': 'Millionaire',   'desc': 'Earn 1M currency',      'category': 'Currency', 'target': 1000000,  'metric': 'currency'},
      {'id': 'cur_10mil', 'title': 'Tycoon',        'desc': 'Earn 10M currency',     'category': 'Currency', 'target': 10000000, 'metric': 'currency'},

      // Taps
      {'id': 'tap_10',    'title': 'Click Novice',      'desc': 'Tap 10 times',        'category': 'Taps', 'target': 10,      'metric': 'taps'},
      {'id': 'tap_100',   'title': 'Click Apprentice',  'desc': 'Tap 100 times',       'category': 'Taps', 'target': 100,     'metric': 'taps'},
      {'id': 'tap_1k',    'title': 'Clicker Pro',       'desc': 'Tap 1,000 times',     'category': 'Taps', 'target': 1000,    'metric': 'taps'},
      {'id': 'tap_10k',   'title': 'Click Legend',      'desc': 'Tap 10,000 times',    'category': 'Taps', 'target': 10000,   'metric': 'taps'},
      {'id': 'tap_100k',  'title': 'Tap Machine',       'desc': 'Tap 100,000 times',   'category': 'Taps', 'target': 100000,  'metric': 'taps'},
      {'id': 'tap_1mil',  'title': 'Tap God',           'desc': 'Tap 1 million times', 'category': 'Taps', 'target': 1000000, 'metric': 'taps'},

      // Upgrades
      {'id': 'up_1',   'title': 'Investor',      'desc': 'Buy 1 upgrade',    'category': 'Upgrades', 'target': 1,   'metric': 'upgrades'},
      {'id': 'up_10',  'title': 'Manager',       'desc': 'Buy 10 upgrades',   'category': 'Upgrades', 'target': 10,  'metric': 'upgrades'},
      {'id': 'up_25',  'title': 'Director',      'desc': 'Buy 25 upgrades',   'category': 'Upgrades', 'target': 25,  'metric': 'upgrades'},
      {'id': 'up_50',  'title': 'Executive',     'desc': 'Buy 50 upgrades',   'category': 'Upgrades', 'target': 50,  'metric': 'upgrades'},
      {'id': 'up_100', 'title': 'Magnate',       'desc': 'Buy 100 upgrades',  'category': 'Upgrades', 'target': 100, 'metric': 'upgrades'},
      {'id': 'up_250', 'title': 'Conglomerate',  'desc': 'Buy 250 upgrades',  'category': 'Upgrades', 'target': 250, 'metric': 'upgrades'},

      // Combo
      {'id': 'combo_1', 'title': 'Getting Started',  'desc': 'Tap 10 & Buy 1',                       'category': 'Combo'},
      {'id': 'combo_2', 'title': 'Small Business',   'desc': 'Tap 100 & 1K Currency',                'category': 'Combo'},
      {'id': 'combo_3', 'title': 'Growing Fast',     'desc': 'Tap 1K & 10 Upgrades',                 'category': 'Combo'},
      {'id': 'combo_4', 'title': 'Mid Tier Mogul',   'desc': '5K Taps & 100K Currency',              'category': 'Combo'},
      {'id': 'combo_5', 'title': 'Corporate Climber','desc': '50 Upgrades & 1M Currency',            'category': 'Combo'},
      {'id': 'combo_6', 'title': 'Capitalist Elite', 'desc': '100K Taps, 100 Upgrades, 10M Currency','category': 'Combo'},
    ];

    _achievements.addAll(all);
    for (var ach in all) {
      _grouped[ach['category']]!.add(ach);
    }
    final maxLength = _grouped.values.map((list) => list.length).reduce((a, b) => a > b ? a : b);
    for (var cat in _grouped.keys) {
      while (_grouped[cat]!.length < maxLength) {
        _grouped[cat]!.add({'placeholder': true});
      }
    }
  }

  void _checkAchievements() {
    bool unlockedAny = false;
    for (final ach in _achievements) {
      final id = ach['id'] as String?;
      if (id == null) continue;
      if (_unlocked.contains(id)) { continue; }

    bool ok = false;
      if (ach['metric'] == 'currency') {
        ok = _totalCurrencyEarned >= (ach['target'] ?? double.infinity);
      } else if (ach['metric'] == 'taps') {
        ok = _totalTaps >= (ach['target'] ?? double.infinity);
      } else if (ach['metric'] == 'upgrades') {
        ok = _totalUpgrades >= (ach['target'] ?? double.infinity);
      } else if ((ach['category'] == 'Combo')) {
        switch (id) {
          case 'combo_1': ok = _totalTaps >= 10 && _totalUpgrades >= 1; break;
          case 'combo_2': ok = _totalTaps >= 100 && _totalCurrencyEarned >= 1000; break;
          case 'combo_3': ok = _totalTaps >= 1000 && _totalUpgrades >= 10; break;
          case 'combo_4': ok = _totalTaps >= 5000 && _totalCurrencyEarned >= 100000; break;
          case 'combo_5': ok = _totalUpgrades >= 50 && _totalCurrencyEarned >= 1000000; break;
          case 'combo_6': ok = _totalTaps >= 100000 && _totalUpgrades >= 100 && _totalCurrencyEarned >= 10000000; break;
        }
      }

      if (ok) {
        _unlocked.add(id);
        unlockedAny = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🏆 Achievement Unlocked: ${ach['title']}')),
          );
        }
      }
    }
    if (unlockedAny) {
      _saveData(silent: true);
    }
  }

  // ===== UI =====
  Widget _buildAchievementPage() {
    final categories = _grouped.keys.toList();
    final maxRows = _grouped[categories[0]]!.length;

    ValueNotifier<int> filter = ValueNotifier<int>(0); // 0=All,1=Locked,2=Unlocked

    double progressFor(Map<String, dynamic> ach) {
      final metric = ach['metric'];
      final target = (ach['target'] ?? 1).toDouble();
      double cur = 0;
      if (metric == 'currency') {
        cur = _totalCurrencyEarned.toDouble();
      } else if (metric == 'taps') {
        cur = _totalTaps.toDouble();
      } else if (metric == 'upgrades') {
        cur = _totalUpgrades.toDouble();
      } 
      return target <= 0 ? 0 : (cur / target).clamp(0, 1);
    }

    bool isUnlocked(Map<String, dynamic> ach) =>
        ach['id'] != null && _unlocked.contains(ach['id']);

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Filter chips
            ValueListenableBuilder<int>(
              valueListenable: filter,
              builder: (_, f, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(label: const Text('All'), selected: f == 0, onSelected: (_) => filter.value = 0),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('Locked'), selected: f == 1, onSelected: (_) => filter.value = 1),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('Unlocked'), selected: f == 2, onSelected: (_) => filter.value = 2),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: categories
                  .map((c) => Expanded(
                        child: Center(
                          child: Text(c, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: filter,
                builder: (_, f, __) {
                  return SingleChildScrollView(
                    child: Column(
                      children: List.generate(maxRows, (i) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(categories.length, (j) {
                            final ach = _grouped[categories[j]]![i];
                            if (ach['placeholder'] == true) {
                              return const Expanded(child: SizedBox(height: 110));
                            }
                            final unlocked = isUnlocked(ach);
                            if (f == 1 && unlocked) return const Expanded(child: SizedBox(height: 110));
                            if (f == 2 && !unlocked) return const Expanded(child: SizedBox(height: 110));

                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.all(8),
                                height: 110,
                                decoration: BoxDecoration(
                                  color: unlocked ? Colors.green[700] : Colors.grey[850],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: unlocked ? Colors.greenAccent : Colors.white10),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(unlocked ? Icons.check_circle : Icons.lock, color: Colors.white),
                                    const SizedBox(height: 6),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        unlocked ? ach['title'] : (ach['title'] ?? '????'),
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    if (!unlocked && (ach['metric'] == 'currency' || ach['metric'] == 'taps' || ach['metric'] == 'upgrades')) ...[
                                      const SizedBox(height: 6),
                                      LinearProgressIndicator(value: progressFor(ach), minHeight: 6),
                                      const SizedBox(height: 4),
                                      Text(_lockedProgressText(ach),
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                          textAlign: TextAlign.center),
                                    ] else if (unlocked && ach.containsKey('desc')) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        ach['desc'],
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lockedProgressText(Map<String, dynamic> ach) {
    final target = (ach['target'] ?? 1).toDouble();
    double cur = 0;
    if (ach['metric'] == 'currency') cur = _totalCurrencyEarned;
    if (ach['metric'] == 'taps') cur = _totalTaps.toDouble();
    if (ach['metric'] == 'upgrades') cur = _totalUpgrades.toDouble();
    return '${_fmtCompact(cur)}/${_fmtCompact(target)}';
  }

  void _handleTap() {
    setState(() {
      _counter += _tapValue;
      _totalTaps++;
      _totalCurrencyEarned += _tapValue;
      _checkAchievements();
    });
  }

  void _startTimer() {
    _passiveTimer?.cancel();
    _passiveTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {
        final earned = _passiveRate * 0.25;
        _counter += earned;
        _totalCurrencyEarned += earned;
        _checkAchievements();
      });
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _counter = prefs.getDouble('counter') ?? 0.0;
    _tapValue = prefs.getDouble('tapValue') ?? 1.0;
    _passiveRate = prefs.getDouble('passiveRate') ?? 0.0;
    _totalTaps = prefs.getInt('totalTaps') ?? 0;
    _totalUpgrades = prefs.getInt('totalUpgrades') ?? 0;
    _totalCurrencyEarned = prefs.getDouble('totalCurrencyEarned') ?? 0.0;
    _lastSavedMillis = prefs.getInt('lastSavedMillis');

    _haptics = prefs.getBool('haptics') ?? true;
    _reduceAnimations = prefs.getBool('reduceAnimations') ?? false;
    _backgroundStyle = prefs.getInt('backgroundStyle') ?? 0;

    final list = prefs.getStringList('unlockedAchievements') ?? [];
    _unlocked.addAll(list);
    for (int i = 0; i < _upgrades.length; i++) {
      _upgrades[i]['count'] = prefs.getInt('upgrade_count_$i') ?? 0;
    }
    if (mounted) setState(() {});
  }

  // Apply idle rewards once after load (CAPPED)
  void _applyIdleRewardsIfAny() {
    if (_lastSavedMillis == null) return;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final elapsedSec = max(0, (nowMillis - _lastSavedMillis!) ~/ 1000);
    if (elapsedSec <= 0 || _passiveRate <= 0) return;

    const capHours = 12; // tweakable
    final cappedSec = min(elapsedSec, capHours * 3600);
    final gained = _passiveRate * cappedSec;
    setState(() {
      _counter += gained;
      _totalCurrencyEarned += gained;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Idle rewards: +${_fmtCompact(gained)}${elapsedSec > cappedSec ? ' (capped to ${capHours}h)' : ''}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveData({bool silent = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('counter', _counter);
    await prefs.setDouble('tapValue', _tapValue);
    await prefs.setDouble('passiveRate', _passiveRate);
    await prefs.setInt('totalTaps', _totalTaps);
    await prefs.setInt('totalUpgrades', _totalUpgrades);
    await prefs.setDouble('totalCurrencyEarned', _totalCurrencyEarned);
    await prefs.setStringList('unlockedAchievements', _unlocked.toList());
    await prefs.setBool('haptics', _haptics);
    await prefs.setBool('reduceAnimations', _reduceAnimations);
    await prefs.setInt('backgroundStyle', _backgroundStyle);
    for (int i = 0; i < _upgrades.length; i++) {
      await prefs.setInt('upgrade_count_$i', _upgrades[i]['count']);
    }
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('lastSavedMillis', nowMillis);
    _lastSavedMillis = nowMillis;

    if (!mounted || silent) return;

    // Throttle save toast
    final now = DateTime.now();
    if (_lastSaveToastAt != null &&
        now.difference(_lastSaveToastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastSaveToastAt = now;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Game saved"), duration: Duration(milliseconds: 300)),
    );
  }

  // Convert global to local inside our Stack
  Offset? _globalToStackLocal(Offset globalPos) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(globalPos);
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double tapDiameter = screenWidth * (2 / 3);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Clicker'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: _openSettings),
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => _buildAchievementPage()));
            },
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveData),
        ],
      ),
      body: Stack(
        key: _stackKey,
        children: [
          _Background(style: _backgroundStyle),

          // ====== Top mini panel (Rate + Tap) ======
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _TopMiniPanel(
              rate: '${_fmtCompact(_passiveRate)}/s',
              tap: _fmtCompact(_tapValue),
            ),
          ),

          // ====== Tap target (atom) ======
          Center(
            child: GestureDetector(
              onTapDown: (details) {
                setState(() => _tapScale = 0.9);
                if (_reduceAnimations) return;
                final local = _globalToStackLocal(details.globalPosition);
                if (local != null) {
                  _fxKey.currentState?.spawnTapFx(local, '+${_fmtCompact(_tapValue)}');
                }
              },
              onTapUp: (_) {
                setState(() => _tapScale = 1.0);
                if (_haptics) HapticFeedback.selectionClick();
                _handleTap();
              },
              onTapCancel: () => setState(() => _tapScale = 1.0),
              child: AnimatedScale(
                scale: _tapScale,
                duration: _tapAnimDuration,
                child: RepaintBoundary(
                  child: AtomGraphic(size: tapDiameter, reduceAnimations: _reduceAnimations),
                ),
              ),
            ),
          ),

          // ====== Floating FX layer (isolated repaint) ======
          if (!_reduceAnimations)
            IgnorePointer(
              ignoring: true,
              child: FloatingFxLayer(key: _fxKey),
            ),

          // ====== Bottom spectrometer (Currency only) ======
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final base = min(c.maxWidth, c.maxHeight) * (2 / 3) * 1.08;
                final w = _clampDouble(base, 260, 520);
                final h = _clampDouble(base * 0.12, 64, 86);
                return Align(
                  alignment: const Alignment(0, 0.55),
                  child: SpectrometerStrip(
                    width: w,
                    height: h,
                    currency: _fmtCompact(_counter),
                    ratePerSec: '',
                    tapValue: '',
                  ),
                );
              },
            ),
          ),

          // ====== Upgrades sheet (polished) ======
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: _isExpanded ? 0 : -screenHeight * 0.6,
            left: 0,
            right: 0,
            height: screenHeight * 0.6,
            child: UpgradeBottomSheet(
              upgrades: _upgrades,
              counter: _counter,
              costMultiplier: _defaultCostMultiplier,
              onBuy: (index, qty, totalCost) {
                setState(() {
                  _counter -= totalCost;
                  _totalUpgrades += qty;
                  _upgrades[index]['count'] = (_upgrades[index]['count'] as int) + qty;
                });
                _recomputeStats();
                _checkAchievements();
              },
            ),
          ),

          // ====== Single Upgrades Button (slides with the sheet) ======
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: _isExpanded ? (screenHeight * 0.6) + 16 : 20,
            child: Center(
              child: ElevatedButton(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade400.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    _isExpanded ? 'Close Upgrades' : 'Upgrades',
                    key: ValueKey<bool>(_isExpanded),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passiveTimer?.cancel();
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveData(silent: true);
    }
  }

  // SETTINGS SHEET
  void _openSettings() async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.grey[950],
      builder: (_) {
        int tmpBg = _backgroundStyle;
        bool tmpHaptics = _haptics;
        bool tmpReduce = _reduceAnimations;
        return StatefulBuilder(
          builder: (context, setModal) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SwitchListTile(title: const Text('Haptics'), value: tmpHaptics, onChanged: (v) => setModal(() => tmpHaptics = v)),
                SwitchListTile(
                  title: const Text('Reduce animations'),
                  subtitle: const Text('Disables floating FX and simplifies visuals'),
                  value: tmpReduce,
                  onChanged: (v) => setModal(() => tmpReduce = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Background style'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: tmpBg,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Indigo/Blue')),
                        DropdownMenuItem(value: 1, child: Text('Graphite')),
                        DropdownMenuItem(value: 2, child: Text('Teal/Navy')),
                      ],
                      onChanged: (v) => setModal(() => tmpBg = v ?? 0),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Reset progress?'),
                            content: const Text('This will clear all saved data. This action cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                            ],
                          ),
                        );
                        if (!mounted) return;
                        if (sure == true) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (!mounted) return;
                          setState(() {
                            _counter = 0;
                            _tapValue = 1.0;
                            _passiveRate = 0;
                            _totalTaps = 0;
                            _totalUpgrades = 0;
                            _totalCurrencyEarned = 0;
                            _unlocked.clear();
                            _lastSavedMillis = null;
                            for (var u in _upgrades) {
                              u['count'] = 0;
                            }
                          });
                          _recomputeStats();
                          if (context.mounted) {
                            Navigator.pop(context); // close settings
                          }
                        }
                      },
                      child: const Text('Reset…'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        setState(() {
                          _haptics = tmpHaptics;
                          _reduceAnimations = tmpReduce;
                          _backgroundStyle = tmpBg;
                        });
                        await _saveData(silent: true);
                        if (!mounted) return;
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===================== Background Styles =====================
class _Background extends StatelessWidget {
  final int style;
  const _Background({required this.style});

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 1:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B0B0F), Color(0xFF1A1B1F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      case 2:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF082032), Color(0xFF1B3B4A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      default:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0E27), Color(0xFF1B1F3B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
    }
  }
}

// ===================== Top Mini Panel (Rate + Tap) =====================
class _TopMiniPanel extends StatelessWidget {
  final String rate;
  final String tap;
  const _TopMiniPanel({required this.rate, required this.tap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, 0.08),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.speed, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rate: $rate',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.touch_app, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap: $tap',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== Spectrometer Strip =====================
class SpectrometerStrip extends StatelessWidget {
  final double width;
  final double height;
  final String currency;
  final String ratePerSec;
  final String tapValue;

  const SpectrometerStrip({
    super.key,
    required this.width,
    required this.height,
    required this.currency,
    required this.ratePerSec,
    required this.tapValue,
  });

  @override
  Widget build(BuildContext context) {
    final onlyCurrency = ratePerSec.isEmpty && tapValue.isEmpty;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          CustomPaint(size: Size(width, height), painter: _SpectrometerStrokePainter()),
          ClipPath(
            clipper: _SpectrometerClipper(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, 0.08)),
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
  final IconData icon;
  final String label;
  final String value;
  const _StatCell({required this.icon, required this.label, required this.value});

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

// ===================== Floating FX layer (isolated) =====================
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
  final List<_ArcParticle> _arcParticles = [];
  final List<_FloatText> _floatTexts = [];

  @override
  void initState() {
    super.initState();
    _fxTicker ??= createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _fxTime = elapsed.inMicroseconds / 1e6;
        _arcParticles.removeWhere((p) => _fxTime - p.t0 >= p.duration);
        _floatTexts.removeWhere((t) => _fxTime - t.t0 >= t.duration);
      });
    })
      ..start();
  }

  @override
  void dispose() {
    _fxTicker?.dispose();
    super.dispose();
  }

  void spawnTapFx(Offset localPos, String text) {
    final now = _fxTime;

    final dirRight = _rng.nextBool() ? 1.0 : -1.0;
    final lateral = lerpDouble(40, 90, _rng.nextDouble())!;
    final rise = lerpDouble(80, 140, _rng.nextDouble())!;
    final dur = lerpDouble(0.7, 1.0, _rng.nextDouble())!;
    final size = lerpDouble(14, 22, _rng.nextDouble())!;
    final bow = lerpDouble(0.3, 0.8, _rng.nextDouble())!;

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mini atoms (arc)
        ..._arcParticles.map((p) {
          final t = ((_fxTime - p.t0) / p.duration).clamp(0.0, 1.0);
          Offset lerpQ(Offset a, Offset b, double t) => Offset(
                a.dx + (b.dx - a.dx) * t,
                a.dy + (b.dy - a.dy) * t,
              );
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
                child: const MiniAtom(size: 18),
              ),
            ),
          );
        }),

        // Floating +X text (compact)
        ..._floatTexts.map((ft) {
          final t = ((_fxTime - ft.t0) / ft.duration).clamp(0.0, 1.0);
          final pos = Offset(
            lerpDouble(ft.start.dx, ft.end.dx, t)!,
            lerpDouble(ft.start.dy, ft.end.dy, t)!,
          );
          final opacity = (1.0 - t);
          return Positioned(
            left: pos.dx,
            top: pos.dy,
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
                    shadows: [Shadow(blurRadius: 6, color: Colors.black, offset: Offset(0, 1))],
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

// ===================== Floating FX model types =====================
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

// ===================== Atom Graphic (main tap target, animated) =====================
class AtomGraphic extends StatefulWidget {
  final double size;
  final bool reduceAnimations;
  const AtomGraphic({super.key, required this.size, this.reduceAnimations = false});

  @override
  State<AtomGraphic> createState() => _AtomGraphicState();
}

class _AtomGraphicState extends State<AtomGraphic>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _timeSeconds = 0.0; // continuously increasing time

  @override
  void initState() {
    super.initState();
    if (!widget.reduceAnimations) {
      _ticker ??= createTicker((elapsed) {
        if (!mounted) return;
        setState(() {
          _timeSeconds = elapsed.inMicroseconds / 1e6;
        });
      })
        ..start();
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
          setState(() {
            _timeSeconds = elapsed.inMicroseconds / 1e6;
          });
        })
          ..start();
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
  final double timeSeconds; // continuous, non-wrapping
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
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawOval(orbitRect, orbitPaint);
      canvas.restore();
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

// ===================== Mini Atom (static) for click particles =====================
class MiniAtom extends StatelessWidget {
  final double size;
  const MiniAtom({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MiniAtomPainter(),
    );
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
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawOval(rect, orbit);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MiniAtomPainter oldDelegate) => false;
}

// ===================== Upgrades Bottom Sheet (polished) =====================
class UpgradeBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> upgrades;
  final double counter;
  final double costMultiplier;
  final void Function(int index, int qty, int totalCost) onBuy;

  const UpgradeBottomSheet({
    super.key,
    required this.upgrades,
    required this.counter,
    required this.costMultiplier,
    required this.onBuy,
  });

  @override
  State<UpgradeBottomSheet> createState() => _UpgradeBottomSheetState();
}

class _UpgradeBottomSheetState extends State<UpgradeBottomSheet> {
  String _sort = 'Default'; // Default, Cost, Owned, Type

  @override
  Widget build(BuildContext context) {
    final items = List.generate(widget.upgrades.length, (i) {
      final u = widget.upgrades[i];
      return ({
        'i': i,
        'label': u['label'],
        'color': u['color'] as Color,
        'baseCost': u['baseCost'] as int,
        'value': u['value'],
        'mult': u['mult'],
        'count': u['count'] as int,
        'type': (u['type'] as String), // 'rate' | 'tap' | 'tapx'
        'costMult': u['costMult'] as double?,
      });
    });

    // Sort visuals
    switch (_sort) {
      case 'Cost':
        items.sort((a, b) {
          final acm = (a['costMult'] as double?) ?? widget.costMultiplier;
          final bcm = (b['costMult'] as double?) ?? widget.costMultiplier;
          final ac = (a['baseCost'] as int) * pow(acm, a['count'] as int);
          final bc = (b['baseCost'] as int) * pow(bcm, b['count'] as int);
          return ac.compareTo(bc);
        });
        break;
      case 'Owned':
        items.sort((b, a) => (a['count'] as int).compareTo(b['count'] as int)); // desc
        break;
      case 'Type':
        items.sort((a, b) => (a['type'] as String).compareTo(b['type'] as String));
        break;
      default:
        // keep original index order
        break;
    }

    return Material(
      color: Colors.grey[900],
      elevation: 10,
      child: Column(
        children: [
          // Sticky header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Text('Upgrades', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                const Text('Sort:', style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sort,
                  dropdownColor: Colors.grey[900],
                  items: const [
                    DropdownMenuItem(value: 'Default', child: Text('Default')),
                    DropdownMenuItem(value: 'Cost', child: Text('Cost')),
                    DropdownMenuItem(value: 'Owned', child: Text('Owned')),
                    DropdownMenuItem(value: 'Type', child: Text('Type')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'Default'),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, visualIdx) {
                final m = items[visualIdx];
                final index = m['i'] as int;
                final color = m['color'] as Color;
                final base = m['baseCost'] as int;
                final count = m['count'] as int;
                final type = m['type'] as String;
                final label = m['label'] as String;
                final value = m['value'];
                final double? perMult = m['costMult'] as double?;

                // Visibility & unlock rules
                final prevCount = index == 0 ? 8 : (widget.upgrades[index - 1]['count'] as int);
                final isVisible = index == 0 || prevCount >= 1;
                final isUnlocked = index == 0 || prevCount >= 8;

                if (!isVisible) return const SizedBox.shrink();

                final costNow = (base * pow(perMult ?? widget.costMultiplier, count)).floor();
                final canBuy1 = isUnlocked && widget.counter >= costNow;

                // Precompute x10
                final costs10 = (context.findAncestorStateOfType<_MyHomePageState>()!)
                    .nextCosts(base, count, widget.costMultiplier, 10, perMult);
                final total10 = costs10.fold<int>(0, (a, b) => a + b);
                final canBuy10 = isUnlocked && widget.counter >= total10;

                // Progress toward unlock (for the next upgrade)
                int? reqOwnedPrev;
                int? ownedPrev;
                if (index + 1 < widget.upgrades.length) {
                  reqOwnedPrev = 8;
                  ownedPrev = widget.upgrades[index]['count'] as int; // current owned, as prev for next
                }

                // Detail text by type
                String detail;
                if (type == 'rate') {
                  detail = '+$value/s';
                } else if (type == 'tapx') {
                  final mult = (m['mult'] as double?) ?? 1.10;
                  detail = '×${mult.toStringAsFixed(2)} tap';
                } else {
                  detail = '+$value/tap';
                }

                return _UpgradeTile(
                  color: color,
                  label: label,
                  detail: detail,
                  count: count,
                  isUnlocked: isUnlocked,
                  lockReason: index == 0 ? null : 'Buy ${widget.upgrades[index - 1]['label']} ×8',
                  costNow: costNow,
                  canBuy1: canBuy1,
                  canBuy10: canBuy10,
                  total10: total10,
                  onBuy1: canBuy1 ? () => widget.onBuy(index, 1, costNow) : null,
                  onBuy10: canBuy10 ? () => widget.onBuy(index, 10, total10) : null,
                  nextProgressLabel: (reqOwnedPrev != null && ownedPrev != null)
                      ? 'Unlock next at $reqOwnedPrev owned · ${ownedPrev.clamp(0, reqOwnedPrev)}/$reqOwnedPrev'
                      : null,
                  nextProgressValue: (reqOwnedPrev != null && ownedPrev != null)
                      ? (ownedPrev / reqOwnedPrev).clamp(0, 1)
                      : null,
                  fmt: (context.findAncestorStateOfType<_MyHomePageState>()!._fmtCompact),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  final Color color;
  final String label;
  final String detail; // e.g., +0.2/s or ×1.15 tap
  final int count;
  final bool isUnlocked;
  final String? lockReason;

  final int costNow;
  final bool canBuy1;
  final bool canBuy10;
  final int total10;

  final VoidCallback? onBuy1;
  final VoidCallback? onBuy10;

  final String? nextProgressLabel;
  final double? nextProgressValue;

  final String Function(num) fmt;

  const _UpgradeTile({
    required this.color,
    required this.label,
    required this.detail,
    required this.count,
    required this.isUnlocked,
    required this.lockReason,
    required this.costNow,
    required this.canBuy1,
    required this.canBuy10,
    required this.total10,
    required this.onBuy1,
    required this.onBuy10,
    required this.fmt,
    this.nextProgressLabel,
    this.nextProgressValue,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.06)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black54)],
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Row(
            children: [
              // Accent pill
              Container(
                width: 6,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + detail
                    Row(
                      children: [
                        Expanded(
                          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text(detail, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Cost + Owned
                    Row(
                      children: [
                        Text('Cost: ${fmt(costNow)}',
                            style: TextStyle(
                              color: canBuy1 ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(width: 12),
                        Text('Owned: $count', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),

                    // Progress to unlock next tier (optional)
                    if (nextProgressLabel != null && nextProgressValue != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: nextProgressValue!.clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(nextProgressLabel!, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Action buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: onBuy1,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canBuy1 ? color.withValues(alpha: 0.9) : Colors.white12,
                      foregroundColor: canBuy1 ? Colors.black : Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: canBuy1 ? 4 : 0,
                    ),
                    child: const Text('Buy'),
                  ),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: 'Tap to buy ×10',
                    child: ElevatedButton(
                      onPressed: onBuy10,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canBuy10 ? Colors.white24 : Colors.white10,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('×10 (${fmt(total10)})', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Lock overlay
          if (!isUnlocked)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text(lockReason ?? 'Locked',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
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
