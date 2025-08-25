// lib/widgets/upgrade_bottom_sheet.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../game/economy.dart';
import '../utils/format.dart'; // fmtTight

class UpgradeBottomSheet extends StatefulWidget {
  const UpgradeBottomSheet({
    super.key,
    required this.upgrades,
    required this.counter,
    required this.costMultiplier,
    required this.onBuy,
    required this.fmtCompact,
  });

  final List<Map<String, dynamic>> upgrades;
  final double counter;
  final double costMultiplier;
  final void Function(int index, int qty, int totalCost) onBuy;
  final String Function(num) fmtCompact;

  @override
  State<UpgradeBottomSheet> createState() => _UpgradeBottomSheetState();
}

class _UpgradeBottomSheetState extends State<UpgradeBottomSheet> {
  String _sort = 'Default'; // Default, Cost, Owned, Type

  @override
  Widget build(BuildContext context) {
    // Build a view model for sorting without mutating source order
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
        'type': (u['type'] as String), // 'rate' | 'tap' | 'tapx' | 'ratex'
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

                // Visibility & unlock rules (same logic as main)
                final prevCount = index == 0 ? 8 : (widget.upgrades[index - 1]['count'] as int);
                final isVisible = index == 0 || prevCount >= 1;
                final isUnlocked = index == 0 || prevCount >= 8;

                if (!isVisible) return const SizedBox.shrink();

                final costNow = upgradeCost(base, count, widget.costMultiplier, perMult);
                final canBuy1 = isUnlocked && widget.counter >= costNow;

                // Precompute x10
                final costs10 = nextCosts(base, count, widget.costMultiplier, 10, perMult);
                final total10 = costs10.fold<int>(0, (a, b) => a + b);
                final canBuy10 = isUnlocked && widget.counter >= total10;

                // Progress toward unlock next tier (visual)
                int? reqOwnedPrev;
                int? ownedPrev;
                if (index + 1 < widget.upgrades.length) {
                  reqOwnedPrev = 8;
                  ownedPrev = widget.upgrades[index]['count'] as int;
                }

                // Detail string reflects stepped additive output
                String detail;
                String? nextHint;

                if (type == 'rate' || type == 'tap') {
                  final unit = type == 'rate' ? '/s' : '/tap';
                  final double baseVal = (value as double?) ?? 0.0;

                  // Current per-unit value after step-ups
                  final perNow = baseVal * valueStepMultiplier(count);

                  // Value per unit if you buy one more now
                  final perNext = baseVal * valueStepMultiplier(count + 1);

                  detail = '+${fmtTight(perNow, maxDecimals: 2)}$unit';
                  final nextAt = nextStepThreshold(count);
                  nextHint = 'Next: +${fmtTight(perNext, maxDecimals: 2)}$unit at $nextAt owned';
                } else if (type == 'tapx') {
                  final mult = (m['mult'] as double?) ?? 1.10;
                  detail = '×${mult.toStringAsFixed(2)} tap';
                } else if (type == 'ratex') {
                  final mult = (m['mult'] as double?) ?? 1.10;
                  detail = '×${mult.toStringAsFixed(2)} /s';
                } else {
                  detail = '+${value ?? 0}';
                }

                return _UpgradeTile(
                  color: color,
                  label: label,
                  detail: detail,
                  nextHint: nextHint,
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
                  fmt: widget.fmtCompact,
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
    this.nextHint,
  });

  final Color color;
  final String label;
  final String detail; // e.g., +0.2/s or ×1.15 tap
  final String? nextHint;
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
                    if (nextHint != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        nextHint!,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
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