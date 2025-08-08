import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

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
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  double _counter = 0;
  double _passiveRate = 0;
  double _tapValue = 1.0;
  double _totalCurrencyEarned = 0;
  int _totalTaps = 0;
  int _totalUpgrades = 0;
  bool _isExpanded = false;
  double _tapScale = 1.0;
  final Duration _tapAnimDuration = const Duration(milliseconds: 100);

  late Timer _passiveTimer;
  late Timer _autoSaveTimer;

  final double _costMultiplier = 1.15;
  final Set<String> _unlocked = {};
  final List<Map<String, dynamic>> _achievements = [];
  final Map<String, List<Map<String, dynamic>>> _grouped = {
    'Currency': [],
    'Taps': [],
    'Upgrades': [],
    'Combo': [],
  };

  final List<Map<String, dynamic>> _upgrades = [
    {'label': 'Piggy Bank', 'color': Colors.teal, 'baseCost': 50, 'value': 0.1, 'count': 0, 'type': 'rate'},
    {'label': 'Coin Printer', 'color': Colors.orange, 'baseCost': 225, 'value': 0.2, 'count': 0, 'type': 'rate'},
    {'label': 'Click Multiplier', 'color': Colors.green, 'baseCost': 950, 'value': 1.0, 'count': 0, 'type': 'tap'},
    {'label': 'Fast Fingers', 'color': Colors.red, 'baseCost': 4000, 'value': 2.0, 'count': 0, 'type': 'tap'},
    {'label': 'Hedge Fund', 'color': Colors.blue, 'baseCost': 17000, 'value': 1.0, 'count': 0, 'type': 'rate'},
    {'label': 'Auto-Clicker Boost', 'color': Colors.pink, 'baseCost': 70000, 'value': 3.0, 'count': 0, 'type': 'tap'},
    {'label': 'Offshore Empire', 'color': Colors.cyan, 'baseCost': 300000, 'value': 5.0, 'count': 0, 'type': 'rate'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAchievements();
    _loadData().then((_) {
      _startTimer();
      _autoSaveTimer = Timer.periodic(const Duration(minutes: 2), (_) => _saveData());
    });
  }

  void _initializeAchievements() {
    final List<Map<String, dynamic>> all = [
      // Currency
      {'id': 'cur_100', 'title': 'Hundredaire', 'desc': 'Earn 100 currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 100},
      {'id': 'cur_1k', 'title': 'Thousandaire', 'desc': 'Earn 1,000 currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 1000},
      {'id': 'cur_10k', 'title': 'Big Spender', 'desc': 'Earn 10,000 currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 10000},
      {'id': 'cur_100k', 'title': 'Wealthy', 'desc': 'Earn 100K currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 100000},
      {'id': 'cur_1mil', 'title': 'Millionaire', 'desc': 'Earn 1M currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 1000000},
      {'id': 'cur_10mil', 'title': 'Tycoon', 'desc': 'Earn 10M currency', 'category': 'Currency', 'check': () => _totalCurrencyEarned >= 10000000},

      // Taps
      {'id': 'tap_10', 'title': 'Click Novice', 'desc': 'Tap 10 times', 'category': 'Taps', 'check': () => _totalTaps >= 10},
      {'id': 'tap_100', 'title': 'Click Apprentice', 'desc': 'Tap 100 times', 'category': 'Taps', 'check': () => _totalTaps >= 100},
      {'id': 'tap_1k', 'title': 'Clicker Pro', 'desc': 'Tap 1,000 times', 'category': 'Taps', 'check': () => _totalTaps >= 1000},
      {'id': 'tap_10k', 'title': 'Click Legend', 'desc': 'Tap 10,000 times', 'category': 'Taps', 'check': () => _totalTaps >= 10000},
      {'id': 'tap_100k', 'title': 'Tap Machine', 'desc': 'Tap 100,000 times', 'category': 'Taps', 'check': () => _totalTaps >= 100000},
      {'id': 'tap_1mil', 'title': 'Tap God', 'desc': 'Tap 1 million times', 'category': 'Taps', 'check': () => _totalTaps >= 1000000},

      // Upgrades
      {'id': 'up_1', 'title': 'Investor', 'desc': 'Buy 1 upgrade', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 1},
      {'id': 'up_10', 'title': 'Manager', 'desc': 'Buy 10 upgrades', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 10},
      {'id': 'up_25', 'title': 'Director', 'desc': 'Buy 25 upgrades', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 25},
      {'id': 'up_50', 'title': 'Executive', 'desc': 'Buy 50 upgrades', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 50},
      {'id': 'up_100', 'title': 'Magnate', 'desc': 'Buy 100 upgrades', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 100},
      {'id': 'up_250', 'title': 'Conglomerate', 'desc': 'Buy 250 upgrades', 'category': 'Upgrades', 'check': () => _totalUpgrades >= 250},

      // Combo
      {'id': 'combo_1', 'title': 'Getting Started', 'desc': 'Tap 10 & Buy 1', 'category': 'Combo', 'check': () => _totalTaps >= 10 && _totalUpgrades >= 1},
      {'id': 'combo_2', 'title': 'Small Business', 'desc': 'Tap 100 & 1K Currency', 'category': 'Combo', 'check': () => _totalTaps >= 100 && _totalCurrencyEarned >= 1000},
      {'id': 'combo_3', 'title': 'Growing Fast', 'desc': 'Tap 1K & 10 Upgrades', 'category': 'Combo', 'check': () => _totalTaps >= 1000 && _totalUpgrades >= 10},
      {'id': 'combo_4', 'title': 'Mid Tier Mogul', 'desc': '5K Taps & 100K Currency', 'category': 'Combo', 'check': () => _totalTaps >= 5000 && _totalCurrencyEarned >= 100000},
      {'id': 'combo_5', 'title': 'Corporate Climber', 'desc': '50 Upgrades & 1M Currency', 'category': 'Combo', 'check': () => _totalUpgrades >= 50 && _totalCurrencyEarned >= 1000000},
      {'id': 'combo_6', 'title': 'Capitalist Elite', 'desc': '100K Taps, 100 Upgrades, 10M Currency', 'category': 'Combo', 'check': () => _totalTaps >= 100000 && _totalUpgrades >= 100 && _totalCurrencyEarned >= 10000000},
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
    for (final ach in _achievements) {
      if (!_unlocked.contains(ach['id']) && ach['check']()) {
        _unlocked.add(ach['id']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🏆 Achievement Unlocked: ${ach['title']}')),
        );
      }
    }
  }

  Widget _buildAchievementPage() {
    final categories = _grouped.keys.toList();
    final maxRows = _grouped[categories[0]]!.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
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
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(maxRows, (i) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(categories.length, (j) {
                        final ach = _grouped[categories[j]]![i];
                        final unlocked = ach['id'] != null && _unlocked.contains(ach['id']);
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(8),
                            height: 110,
                            decoration: BoxDecoration(
                              color: ach['placeholder'] == true
                                  ? Colors.transparent
                                  : unlocked
                                      ? Colors.green[700]
                                      : Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ach['placeholder'] == true
                                ? const SizedBox()
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(unlocked ? Icons.check_circle : Icons.lock, color: Colors.white),
                                      const SizedBox(height: 6),
                                      if (unlocked && ach.containsKey('desc') && ach['desc'] != null)
                                        Tooltip(
                                          message: (ach['desc'] ?? 'No description').toString(),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              ach['title'],
                                              style: const TextStyle(color: Colors.white, fontSize: 14),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                            ),
                                          ),
                                        )
                                      else
                                        Text(
                                          '????',
                                          style: const TextStyle(color: Colors.white, fontSize: 14),
                                          textAlign: TextAlign.center,
                                        ),
                                    ],
                                  ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    _passiveTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
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
    final list = prefs.getStringList('unlockedAchievements') ?? [];
    _unlocked.addAll(list);
    for (int i = 0; i < _upgrades.length; i++) {
      _upgrades[i]['count'] = prefs.getInt('upgrade_count_$i') ?? 0;
    }
    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('counter', _counter);
    prefs.setDouble('tapValue', _tapValue);
    prefs.setDouble('passiveRate', _passiveRate);
    prefs.setInt('totalTaps', _totalTaps);
    prefs.setInt('totalUpgrades', _totalUpgrades);
    prefs.setDouble('totalCurrencyEarned', _totalCurrencyEarned);
    prefs.setStringList('unlockedAchievements', _unlocked.toList());
    for (int i = 0; i < _upgrades.length; i++) {
      prefs.setInt('upgrade_count_$i', _upgrades[i]['count']);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Game saved"), duration: Duration(milliseconds: 200)),
    );
  }

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
          IconButton(icon: const Icon(Icons.emoji_events), onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => _buildAchievementPage()));
          }),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveData),
          IconButton(icon: const Icon(Icons.delete_forever), onPressed: () async {
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
              for (var u in _upgrades) {
                u['count'] = 0;
              }
            });
          }),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A0E27), Color(0xFF1B1F3B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.1),
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('💰 Currency: ${_counter.toStringAsFixed(1)}', style: const TextStyle(fontSize: 22, color: Colors.white)),
                      Text('⏱ Rate: ${_passiveRate.toStringAsFixed(1)}/sec', style: const TextStyle(fontSize: 22, color: Colors.white)),
                      Text('👆 Tap: ${_tapValue.toStringAsFixed(1)}', style: const TextStyle(fontSize: 22, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _tapScale = 0.9),
              onTapUp: (_) {
                setState(() => _tapScale = 1.0);
                _handleTap();
              },
              onTapCancel: () => setState(() => _tapScale = 1.0),
              child: AnimatedScale(
                scale: _tapScale,
                duration: _tapAnimDuration,
                child: AtomGraphic(size: tapDiameter),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                child: Text(_isExpanded ? 'Upgrades' : 'Upgrades'),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: _isExpanded ? 0 : -screenHeight * 0.6,
            left: 0,
            right: 0,
            height: screenHeight * 0.6,
            child: Material(
              color: Colors.grey[900],
              elevation: 10,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _isExpanded = false),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _upgrades.length,
                      itemBuilder: (context, index) {
                        final upgrade = _upgrades[index];
                        final int cost = getCurrentCost(upgrade['baseCost'], upgrade['count'], _costMultiplier);
                        final bool isUnlocked = index == 0 || _upgrades[index - 1]['count'] >= 8;
                        final bool shouldShow = index == 0 || _upgrades[index - 1]['count'] > 0 || (index > 1 && _upgrades[index - 2]['count'] >= 8);

                        if (!shouldShow) return const SizedBox.shrink();

                        return InkWell(
                          onTap: isUnlocked && _counter >= cost
                              ? () {
                                  setState(() {
                                    _counter -= cost;
                                    _totalUpgrades++;
                                    if (upgrade['type'] == 'rate') {
                                      _passiveRate += upgrade['value'];
                                    } else {
                                      _tapValue += upgrade['value'];
                                    }
                                    upgrade['count']++;
                                    _checkAchievements();
                                  });
                                }
                              : null,
                          child: Container(
                            color: isUnlocked ? upgrade['color'] : Colors.grey[800],
                            height: 100,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              isUnlocked
                                  ? '${upgrade['label']} (+${upgrade['value']}/${upgrade['type']}) - Cost: $cost - Owned: ${upgrade['count']}'
                                  : '????',
                              style: const TextStyle(fontSize: 20, color: Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int getCurrentCost(int base, int count, double multiplier) {
    return (base * pow(multiplier, count)).floor();
  }

  @override
  void dispose() {
    _passiveTimer.cancel();
    _autoSaveTimer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveData();
    }
  }
}

// ===================== Atom Graphic (no assets, seamless) =====================
class AtomGraphic extends StatefulWidget {
  final double size;
  const AtomGraphic({super.key, required this.size});

  @override
  State<AtomGraphic> createState() => _AtomGraphicState();
}

class _AtomGraphicState extends State<AtomGraphic> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _timeSeconds = 0.0; // continuously increasing time

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // elapsed is the total time since the ticker started; it never resets.
      setState(() {
        _timeSeconds = elapsed.inMicroseconds / 1e6;
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _AtomPainter(timeSeconds: _timeSeconds),
    );
  }
}

class _AtomPainter extends CustomPainter {
  final double timeSeconds; // continuous, non-wrapping
  _AtomPainter({required this.timeSeconds});

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

    // Helper: position an electron with angular speed (rad/s), tilt, and phase
    void drawElectron({
      required double angularSpeed, // radians per second
      required double tiltDeg,
      required double phase,       // radians
      double scale = 1.0,
    }) {
      final tilt = tiltDeg * pi / 180;
      final a = (orbitRect.width / 2) * scale;
      final b = (orbitRect.height / 2) * scale;

      final theta = angularSpeed * timeSeconds + phase; // continuous, no reset
      final x = a * cos(theta);
      final y = b * sin(theta);

      // rotate (x, y) by tilt and translate to center
      final xr = x * cos(tilt) - y * sin(tilt);
      final yr = x * sin(tilt) + y * cos(tilt);
      final pos = Offset(center.dx + xr, center.dy + yr);

      canvas.drawCircle(pos, radius * 0.08, electronPaint);
    }

    // Different speeds and phase offsets for visual interest
    // (values tuned for smooth, non-synchronized motion)
    drawElectron(angularSpeed: 1.8, tiltDeg:   0, phase: 0.0,      scale: 0.98);
    drawElectron(angularSpeed: 2.3, tiltDeg:  60, phase: pi / 3,   scale: 0.98);
    drawElectron(angularSpeed: 2.8, tiltDeg: 120, phase: 2 * pi/3, scale: 0.98);
  }

  @override
  bool shouldRepaint(covariant _AtomPainter oldDelegate) => oldDelegate.timeSeconds != timeSeconds;
}