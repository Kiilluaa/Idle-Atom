import 'package:flutter/material.dart';

/// Strongly-typed upgrade model.
class Upgrade {
  final String label;
  final Color color;
  final int baseCost;
  final String type; // 'rate' | 'tap' | 'tapx' | 'ratex'
  final double costMult;
  final double? value; // for 'rate' and 'tap'
  final double? mult;  // for 'tapx' or 'ratex'
  int count;

  Upgrade({
    required this.label,
    required this.color,
    required this.baseCost,
    required this.type,
    required this.costMult,
    this.value,
    this.mult,
    this.count = 0,
  });

  Upgrade copyWith({int? count}) => Upgrade(
    label: label,
    color: color,
    baseCost: baseCost,
    type: type,
    costMult: costMult,
    value: value,
    mult: mult,
    count: count ?? this.count,
  );
}

/// Factory to create a fresh list (with zeroed counts)
List<Upgrade> createDefaultUpgrades() => [
  Upgrade(label: 'Ion Trap',         color: Colors.teal,   baseCost: 50,      type: 'rate', costMult: 1.13, value: 0.1),
  Upgrade(label: 'Fusion Chamber',   color: Colors.orange, baseCost: 225,     type: 'rate', costMult: 1.14, value: 0.2),
  Upgrade(label: 'Quantum Tuner',    color: Colors.green,  baseCost: 950,     type: 'tapx', costMult: 1.14, mult: 1.15),
  Upgrade(label: 'Muon Gauntlet',    color: Colors.red,    baseCost: 4000,    type: 'tap',  costMult: 1.15, value: 2.0),
  Upgrade(label: 'Research Grant',   color: Colors.blue,   baseCost: 17000,   type: 'rate', costMult: 1.15, value: 1.0),
  Upgrade(label: 'Nanobot Swarm',    color: Colors.pink,   baseCost: 70000,   type: 'tap',  costMult: 1.16, value: 3.0),
  Upgrade(label: 'Dyson Swarm',      color: Colors.cyan,   baseCost: 300000,  type: 'rate', costMult: 1.16, value: 5.0),
  Upgrade(label: 'Quantum Overclock',color: Colors.purple, baseCost: 1200000, type: 'tapx', costMult: 1.16, mult: 1.25),
];