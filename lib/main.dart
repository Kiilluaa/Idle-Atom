import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';

// Project imports
import 'game/economy.dart';                  // milestoneMult, cost helpers
import 'game/achievements.dart';             // Achievements.check
import 'game/persistence.dart';              // Persistence.load/save
import 'utils/format.dart';                  // fmtCompact
import 'widgets/upgrade_bottom_sheet.dart';  // UpgradeBottomSheet UI
import 'widgets/fx_layer.dart' as fx;        // FloatingFxLayer (+State)
import 'widgets/atom_graphics.dart';         // AtomGraphic, MiniAtom
import 'widgets/top_mini_panel.dart';        // TopMiniPanel
import 'widgets/spectrometer_strip.dart';    // SpectrometerStrip
import 'pages/achievements_page.dart';       // Achievements UI page

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
        snackBarTheme:
            const SnackBarThemeData(behavior: SnackBarBehavior.floating),
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

  // Global default cost multiplier (each upgrade can override with costMult)
  final double _defaultCostMultiplier = 1.15;

  // Unlocked achievement IDs
  final Set<String> _unlocked = {};

  // Settings (kept local; persisted via SharedPreferences)
  bool _haptics = true;
  bool _reduceAnimations = false;
  int _backgroundStyle = 0;

  // Idle rewards timestamp
  int? _lastSavedMillis;

  // Save throttling (UI toast)
  DateTime? _lastSaveToastAt;

  // ======== Upgrades (science/atom theme) ========
  final List<Map<String, dynamic>> _upgrades = [
    {
      'label': 'Ion Trap',
      'color': Colors.teal,
      'baseCost': 50,
      'value': 0.1,
      'count': 0,
      'type': 'rate',
      'costMult': 1.13
    },
    {
      'label': 'Fusion Chamber',
      'color': Colors.orange,
      'baseCost': 225,
      'value': 0.2,
      'count': 0,
      'type': 'rate',
      'costMult': 1.14
    },
    {
      'label': 'Quantum Tuner',
      'color': Colors.green,
      'baseCost': 950,
      'mult': 1.15,
      'count': 0,
      'type': 'tapx',
      'costMult': 1.14
    },
    {
      'label': 'Muon Gauntlet',
      'color': Colors.red,
      'baseCost': 4000,
      'value': 2.0,
      'count': 0,
      'type': 'tap',
      'costMult': 1.15
    },
    {
      'label': 'Research Grant',
      'color': Colors.blue,
      'baseCost': 17000,
      'value': 1.0,
      'count': 0,
      'type': 'rate',
      'costMult': 1.15
    },
    {
      'label': 'Nanobot Swarm',
      'color': Colors.pink,
      'baseCost': 70000,
      'value': 3.0,
      'count': 0,
      'type': 'tap',
      'costMult': 1.16
    },
    {
      'label': 'Dyson Swarm',
      'color': Colors.cyan,
      'baseCost': 300000,
      'value': 5.0,
      'count': 0,
      'type': 'rate',
      'costMult': 1.16
    },
    {
      'label': 'Quantum Overclock',
      'color': Colors.purple,
      'baseCost': 1200000,
      'mult': 1.25,
      'count': 0,
      'type': 'tapx',
      'costMult': 1.16
    },
  ];

  // ======== FX layer control ========
  final GlobalKey<fx.FloatingFxLayerState> _fxKey =
      GlobalKey<fx.FloatingFxLayerState>();
  final GlobalKey _stackKey = GlobalKey();

  double _clampDouble(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  // Cookie-style milestones: +10% per 25, +15% per 50, ×2 per 100
  void _recomputeStats() {
    double rate = 0.0;
    double tapBase = 1.0; // base tap
    double tapFlat = 0.0; // additive
    double tapMult = 1.0; // multiplicative
    double rateMult = 1.0; // if you add 'ratex' items later

    for (final u in _upgrades) {
      final int c = (u['count'] as int);
      if (c == 0) continue;
      final String t = u['type'] as String;
      final double milestone = milestoneMult(c);

      if (t == 'rate') {
        rate += c * (u['value'] as double) * milestone;
      } else if (t == 'tap') {
        tapFlat += c * (u['value'] as double) * milestone;
      } else if (t == 'tapx') {
        final double m = (u['mult'] as double? ?? 1.10);
        tapMult *= pow(m, c) * milestone;
      } else if (t == 'ratex') {
        final double m = (u['mult'] as double? ?? 1.10);
        rateMult *= pow(m, c) * milestone;
      }
    }

    setState(() {
      _passiveRate = rate * rateMult;
      _tapValue = (tapBase + tapFlat) * tapMult;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData().then((_) async {
      _recomputeStats(); // recompute before idle rewards
      _applyIdleRewardsIfAny();
      await _saveData(silent: true);
      _startTimer();
      _autoSaveTimer =
          Timer.periodic(const Duration(minutes: 2), (_) => _saveData(silent: true));
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
      });
      _checkAchievements();
    });
  }

  void _handleTap() {
    setState(() {
      _counter += _tapValue;
      _totalTaps++;
      _totalCurrencyEarned += _tapValue;
    });
    _checkAchievements();
  }

  Future<void> _loadData() async {
    final snap = await Persistence.load(numUpgrades: _upgrades.length);
    _counter = (snap['counter'] as num?)?.toDouble() ?? 0.0;
    _tapValue = (snap['tapValue'] as num?)?.toDouble() ?? 1.0;
    _passiveRate = (snap['passiveRate'] as num?)?.toDouble() ?? 0.0;
    _totalTaps = snap['totalTaps'] as int? ?? 0;
    _totalUpgrades = snap['totalUpgrades'] as int? ?? 0;
    _totalCurrencyEarned = (snap['totalCurrencyEarned'] as num?)?.toDouble() ?? 0.0;
    _haptics = snap['haptics'] as bool? ?? true;
    _reduceAnimations = snap['reduceAnimations'] as bool? ?? false;
    _backgroundStyle = snap['backgroundStyle'] as int? ?? 0;
    _lastSavedMillis = snap['lastSavedMillis'] as int?;

    final unlockedList = (snap['unlockedAchievements'] as List).cast<String>();
    _unlocked
      ..clear()
      ..addAll(unlockedList);

    // restore upgrade counts
    final counts = (snap['upgradeCounts'] as List).cast<int>();
    for (int i = 0; i < _upgrades.length; i++) {
      _upgrades[i]['count'] = counts[i];
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
        content: Text(
            'Idle rewards: +${fmtCompact(gained)}${elapsedSec > cappedSec ? ' (capped to ${capHours}h)' : ''}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveData({bool silent = false}) async {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final upgradeCounts =
        _upgrades.map<int>((u) => (u['count'] as int)).toList();

    await Persistence.save(
      counter: _counter,
      tapValue: _tapValue,
      passiveRate: _passiveRate, // still persisted for compatibility
      totalTaps: _totalTaps,
      totalUpgrades: _totalUpgrades,
      totalCurrencyEarned: _totalCurrencyEarned,
      unlockedAchievements: _unlocked.toList(),
      haptics: _haptics,
      reduceAnimations: _reduceAnimations,
      backgroundStyle: _backgroundStyle,
      upgradeCounts: upgradeCounts,
      nowMillis: nowMillis,
    );
    _lastSavedMillis = nowMillis;

    if (!mounted || silent) return;

    // Throttle save toast to avoid spam
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

  void _checkAchievements() {
    final newly = Achievements.check(
      totalCurrency: _totalCurrencyEarned,
      totalTaps: _totalTaps,
      totalUpgrades: _totalUpgrades,
      alreadyUnlocked: _unlocked,
    );
    if (newly.isEmpty) return;

    for (final id in newly) {
      final ach = Achievements.all.firstWhere((a) => a.id == id);
      _unlocked.add(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🏆 Achievement Unlocked: ${ach.title}')),
        );
      }
    }
    _saveData(silent: true);
  }

  // Convert global to local inside our Stack
  Offset? _globalToStackLocal(Offset globalPos) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(globalPos);
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
                const Text('Settings',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SwitchListTile(
                    title: const Text('Haptics'),
                    value: tmpHaptics,
                    onChanged: (v) => setModal(() => tmpHaptics = v)),
                SwitchListTile(
                  title: const Text('Reduce animations'),
                  subtitle:
                      const Text('Disables floating FX and simplifies visuals'),
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
                            content: const Text(
                                'This will clear all saved data. This action cannot be undone.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton.tonal(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Reset')),
                            ],
                          ),
                        );
                        if (!mounted) return;
                        if (sure == true) {
                          await Persistence.clearAll();
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
                          if (context.mounted) Navigator.pop(context);
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
                        if (context.mounted) Navigator.pop(context);
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
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: _openSettings),
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AchievementsPage(unlocked: _unlocked),
                ),
              );
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
            child: TopMiniPanel(
              rate: '${fmtCompact(_passiveRate)}/s',
              tap: fmtCompact(_tapValue),
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
                  _fxKey.currentState
                      ?.spawnTapFx(local, '+${fmtCompact(_tapValue)}');
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
                  child: AtomGraphic(
                      size: tapDiameter, reduceAnimations: _reduceAnimations),
                ),
              ),
            ),
          ),

          // ====== Floating FX layer (isolated repaint) ======
          if (!_reduceAnimations)
            IgnorePointer(
              ignoring: true,
              child: fx.FloatingFxLayer(key: _fxKey),
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
                    currency: fmtCompact(_counter),
                    ratePerSec: '',
                    tapValue: '',
                  ),
                );
              },
            ),
          ),

          // ====== Upgrades sheet ======
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
              fmtCompact: fmtCompact,
              onBuy: (index, qty, totalCost) {
                setState(() {
                  _counter -= totalCost;
                  _totalUpgrades += qty;
                  _upgrades[index]['count'] =
                      (_upgrades[index]['count'] as int) + qty;
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
                  backgroundColor:
                      Colors.deepPurple.shade400.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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

  int getCurrentCost(int base, int count, double defaultMult, [double? perMult]) {
    final m = perMult ?? defaultMult;
    return (base * pow(m, count)).floor();
  }

  @override
  void dispose() {
    _passiveTimer?.cancel();
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ===================== Background Styles =====================
class _Background extends StatelessWidget {
  const _Background({required this.style});
  final int style;

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