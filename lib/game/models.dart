// lib/game/models.dart
import 'package:flutter/material.dart';

enum UpgradeType { rate, tap, tapx, ratex }

class Upgrade {
  final String label;
  final int baseCost;
  final Color color;
  final UpgradeType type;
  final double? value; // for rate/tap
  final double? mult;  // for tapx/ratex
  final double? costMult;
  int count;

  Upgrade({
    required this.label,
    required this.baseCost,
    required this.color,
    required this.type,
    this.value,
    this.mult,
    this.costMult,
    this.count = 0,
  });

  // --- Map interop to migrate gradually from your current List<Map> ---
  static UpgradeType _typeFromString(String s) {
    switch (s) {
      case 'rate':  return UpgradeType.rate;
      case 'tap':   return UpgradeType.tap;
      case 'tapx':  return UpgradeType.tapx;
      case 'ratex': return UpgradeType.ratex;
      default:      return UpgradeType.tap; // fallback
    }
  }

  static String _typeToString(UpgradeType t) {
    switch (t) {
      case UpgradeType.rate:  return 'rate';
      case UpgradeType.tap:   return 'tap';
      case UpgradeType.tapx:  return 'tapx';
      case UpgradeType.ratex: return 'ratex';
    }
  }

  factory Upgrade.fromMap(Map<String, dynamic> m) => Upgrade(
    label: m['label'] as String,
    baseCost: m['baseCost'] as int,
    color: m['color'] as Color,
    type: _typeFromString(m['type'] as String),
    value: (m['value'] as num?)?.toDouble(),
    mult:  (m['mult']  as num?)?.toDouble(),
    costMult: (m['costMult'] as num?)?.toDouble(),
    count: m['count'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'label': label,
    'baseCost': baseCost,
    'color': color,
    'type': _typeToString(type),
    'value': value,
    'mult': mult,
    'costMult': costMult,
    'count': count,
  };

  static List<Upgrade> listFromMaps(List<Map<String, dynamic>> src) =>
      src.map(Upgrade.fromMap).toList();

  static List<Map<String, dynamic>> listToMaps(List<Upgrade> src) =>
      src.map((u) => u.toMap()).toList();
}
