import 'package:flutter/material.dart';
import '../game/achievements.dart'; // uses Achievements.all

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key, required this.unlocked});

  /// Set of unlocked achievement IDs (from persistence / game state).
  final Set<String> unlocked;

  @override
  Widget build(BuildContext context) {
    // Build grouped grid from the canonical list
    final categories = const ['Currency', 'Taps', 'Upgrades', 'Combo'];
    final Map<String, List<Map<String, dynamic>>> grouped = {
      for (final c in categories) c: <Map<String, dynamic>>[]
    };

    for (final a in Achievements.all) {
      grouped[a.category]!.add({
        'id': a.id,
        'title': a.title,
        'desc': a.desc,
        'category': a.category,
      });
    }

    // Pad columns to same length to keep a nice grid
    final maxLen =
        grouped.values.map((l) => l.length).reduce((a, b) => a > b ? a : b);
    for (final k in grouped.keys) {
      while (grouped[k]!.length < maxLen) {
        grouped[k]!.add({'placeholder': true});
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: categories
                  .map(
                    (c) => Expanded(
                      child: Center(
                        child: Text(
                          c,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(maxLen, (i) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(categories.length, (j) {
                        final ach = grouped[categories[j]]![i];
                        if (ach['placeholder'] == true) {
                          return const Expanded(child: SizedBox(height: 110));
                        }
                        final isUnlocked =
                            ach['id'] != null && unlocked.contains(ach['id']);
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(8),
                            height: 110,
                            decoration: BoxDecoration(
                              color: isUnlocked
                                  ? Colors.green[700]
                                  : Colors.grey[850],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isUnlocked
                                    ? Colors.greenAccent
                                    : Colors.white10,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isUnlocked
                                      ? Icons.check_circle
                                      : Icons.lock,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isUnlocked
                                        ? ach['title']
                                        : (ach['title'] ?? '????'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
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
}