import 'package:flutter/material.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.backgroundStyle,
    required this.haptics,
    required this.reduceAnimations,
    required this.onSave,
    required this.onReset,
  });

  final int backgroundStyle;
  final bool haptics;
  final bool reduceAnimations;

  /// Called when the user taps Save.
  /// Persisting is the responsibility of the caller.
  final Future<void> Function({
    required int backgroundStyle,
    required bool haptics,
    required bool reduceAnimations,
  }) onSave;

  /// Called when the user confirms a full reset.
  final Future<void> Function() onReset;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late int tmpBg = widget.backgroundStyle;
  late bool tmpHaptics = widget.haptics;
  late bool tmpReduce = widget.reduceAnimations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Haptics'),
            value: tmpHaptics,
            onChanged: (v) => setState(() => tmpHaptics = v),
          ),
          SwitchListTile(
            title: const Text('Reduce animations'),
            subtitle: const Text('Disables floating FX and simplifies visuals'),
            value: tmpReduce,
            onChanged: (v) => setState(() => tmpReduce = v),
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
                onChanged: (v) => setState(() => tmpBg = v ?? 0),
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
                  if (sure == true) {
                    await widget.onReset();
                    if (context.mounted) Navigator.pop(context); // close sheet
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
                  await widget.onSave(
                    backgroundStyle: tmpBg,
                    haptics: tmpHaptics,
                    reduceAnimations: tmpReduce,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}