import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:flutter/services.dart';

// Game & data
import 'game/game_state.dart';
import 'game/upgrades.dart';
import 'game/persistence.dart';
import 'game/achievements.dart'; // ⬅️ for title lookup

// Utils & widgets
import 'utils/format.dart';
import 'widgets/background.dart';
import 'widgets/top_mini_panel.dart';
import 'widgets/spectrometer_strip.dart';
import 'widgets/upgrade_bottom_sheet.dart';
import 'widgets/fx_layer.dart' as fx;
import 'widgets/atom_graphics.dart';
import 'widgets/settings_sheet.dart';
import 'pages/achievements_page.dart';

void main() {
  runApp(const MyApp());
}

// Single MaterialApp so tests can pump `MyApp()`.
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
      home: const _Root(),
    );
  }
}

// Root that owns the GameState and shows the home UI once loaded.
class _Root extends StatefulWidget {
  const _Root({super.key});
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final GameState game = GameState(initialUpgrades: createDefaultUpgrades());
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGameChanged);
    game.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  void _onGameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return MyHomePage(game: game);
  }
}

// ===================== HOME PAGE =====================
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.game});
  final GameState game;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isExpanded = false;
  double _tapScale = 1.0;
  final Duration _tapAnimDuration = const Duration(milliseconds: 100);

  // FX layer control
  final GlobalKey<fx.FloatingFxLayerState> _fxKey = GlobalKey<fx.FloatingFxLayerState>();
  final GlobalKey _stackKey = GlobalKey();

  // Throttle for the "Game saved" banner
  DateTime? _lastSaveToastAt;

  // Track GameState change versions so we can react once per tick
  int _lastSeenSaveVersion = 0;
  int _lastSeenUnlockVersion = 0; // ⬅️ track achievement unlocks

  @override
  void initState() {
    super.initState();
    _lastSeenSaveVersion = widget.game.saveVersion;
    _lastSeenUnlockVersion = widget.game.unlockVersion; // ⬅️ init
    widget.game.addListener(_onGameEvent);
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGameEvent);
    super.dispose();
  }

  // React to GameState events (autosave + achievement popups)
  void _onGameEvent() {
    if (!mounted) return;
    final g = widget.game;

    // ===== Autosave toast =====
    if (g.saveVersion != _lastSeenSaveVersion) {
      _lastSeenSaveVersion = g.saveVersion;

      // Only toast for autosaves; manual saves use _save()
      if (g.lastSaveWasAuto) {
        final now = DateTime.now();
        if (_lastSaveToastAt == null ||
            now.difference(_lastSaveToastAt!) >= const Duration(seconds: 3)) {
          _lastSaveToastAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Game saved'),
              duration: Duration(milliseconds: 300),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    // ===== Achievement popup =====
    if (g.unlockVersion != _lastSeenUnlockVersion) {
      _lastSeenUnlockVersion = g.unlockVersion;

      final id = g.lastUnlockedId;
      if (id != null) {
        // Find achievement title
        String title = id;
        try {
          final a = Achievements.all.firstWhere((x) => x.id == id);
          title = a.title;
        } catch (_) {
          // keep id as fallback
        }

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Achievement unlocked: $title'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'VIEW',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AchievementsPage(unlocked: g.unlocked)),
                  );
                },
              ),
            ),
          );
      }
    }
  }

  // Manual save helper with toast and throttling
  Future<void> _save({bool silent = false}) async {
    await widget.game.save(silent: silent);
    if (!mounted || silent) return;

    final now = DateTime.now();
    if (_lastSaveToastAt != null && now.difference(_lastSaveToastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastSaveToastAt = now;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Game saved'),
        duration: Duration(milliseconds: 300),
        behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.grey[950],
      builder: (_) => SettingsSheet(
        backgroundStyle: widget.game.backgroundStyle,
        haptics: widget.game.haptics,
        reduceAnimations: widget.game.reduceAnimations,
        onSave: ({required int backgroundStyle, required bool haptics, required bool reduceAnimations}) async {
          setState(() {
            widget.game.backgroundStyle = backgroundStyle;
            widget.game.haptics = haptics;
            widget.game.reduceAnimations = reduceAnimations;
          });
          await widget.game.save(silent: true);
        },
        onReset: () async {
          await Persistence.clearAll();
          setState(() {
            widget.game.counter = 0;
            widget.game.tapValue = 1.0;
            widget.game.passiveRate = 0;
            widget.game.totalTaps = 0;
            widget.game.totalUpgrades = 0;
            widget.game.totalCurrencyEarned = 0;
            widget.game.unlocked.clear();
            for (var u in widget.game.upgrades) {
              u.count = 0;
            }
            widget.game.recomputeStats();
          });
        },
      ),
    );
  }

  // Convert global to local inside our Stack
  Offset? _globalToStackLocal(Offset globalPos) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(globalPos);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AchievementsPage(unlocked: g.unlocked)),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: () => _save()),
        ],
      ),
      body: Stack(
        key: _stackKey,
        children: [
          Background(style: g.backgroundStyle),

          // ====== Top mini panel + Buff overlay (when active) ======
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TopMiniPanel(
                  rate: '${fmtTight(g.currentPassiveRate, maxDecimals: 2)}/s',
                  // show boosted value live
                  tap: fmtNumber(g.currentTapValue, maxDecimals: 2),
                ),
                const SizedBox(height: 6),
                if (g.isBuffActive && g.buffRemainingMs > 0 && g.buffTotalMs > 0)
                  _BuffOverlay(
                    remainingMs: g.buffRemainingMs,
                    totalMs: g.buffTotalMs,
                  ),
              ],
            ),
          ),

          // ====== Tap target (atom) ======
          Center(
            child: GestureDetector(
              onTapDown: (details) {
                setState(() => _tapScale = 0.9);
                if (g.reduceAnimations) return;
                final local = _globalToStackLocal(details.globalPosition);
                if (local != null) {
                  _fxKey.currentState?.spawnTapFx(local, '+${fmtNumber(g.currentTapValue, maxDecimals: 2)}');
                }
              },
              onTapUp: (_) {
                setState(() => _tapScale = 1.0);
                if (g.haptics) HapticFeedback.selectionClick();
                g.handleTap();
              },
              onTapCancel: () => setState(() => _tapScale = 1.0),
              child: AnimatedScale(
                scale: _tapScale,
                duration: _tapAnimDuration,
                child: RepaintBoundary(
                  child: AtomGraphic(size: tapDiameter, reduceAnimations: g.reduceAnimations),
                ),
              ),
            ),
          ),

          // ====== Floating FX layer (isolated repaint) ======
          if (!g.reduceAnimations)
            IgnorePointer(
              ignoring: true,
              child: fx.FloatingFxLayer(key: _fxKey),
            ),

          // ====== Bottom spectrometer (Currency + Stats) ======
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
                    currency: fmtCompact(g.counter),
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
              upgrades: g.upgrades.map((u) => {
                'label': u.label,
                'color': u.color,
                'baseCost': u.baseCost,
                'value': u.value,
                'mult': u.mult,
                'count': u.count,
                'type': u.type,
                'costMult': u.costMult,
              }).toList(),
              counter: g.counter,
              costMultiplier: 1.15,
              fmtCompact: fmtCompact,
              onBuy: (index, qty, totalCost) {
                // Let GameState own pricing and deduction to avoid drift/double-charge.
                final ok = g.buyUpgrade(index, qty);
                if (ok) {
                  setState(() {});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not enough currency')),
                  );
                }
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

  double _clampDouble(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}

// ===================== PRIVATE WIDGET: Buff Overlay =====================

class _BuffOverlay extends StatelessWidget {
  const _BuffOverlay({required this.remainingMs, required this.totalMs});

  final int remainingMs;
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    final double ratio =
        (totalMs <= 0) ? 0.0 : (remainingMs / totalMs).clamp(0.0, 1.0);
    final double secsLeft = remainingMs / 1000.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E28).withValues(alpha: 0.85),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top line with text
          Row(
            children: [
              const Icon(Icons.bolt, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '×10 BOOST — ${secsLeft.toStringAsFixed(1)}s left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar that shrinks from right to left
          SizedBox(
            height: 6,
            child: Stack(
              children: [
                // Background track
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Right-aligned shrinking fill
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerRight,
                      widthFactor: ratio, // 1.0 -> full, 0.0 -> empty
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
