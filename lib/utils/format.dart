// lib/utils/format.dart
import 'dart:math';

// -------- internal helpers --------
String _stripTrailingZeros(String s) {
  if (!s.contains('.')) return s;
  s = s.replaceFirst(RegExp(r'0+$'), ''); // remove trailing zeros
  s = s.replaceFirst(RegExp(r'\.$'), ''); // remove trailing dot
  return s;
}

// Truncate to [decimals] places (no rounding).
double _truncateTo(double n, int decimals) {
  final factor = pow(10, decimals);
  return (n * factor).truncateToDouble() / factor;
}

// -------- public formatters --------

// Compact number formatter for game values (truncated decimals).
// Examples:
//   2150      -> "2.1K"
//   5500000   -> "5.5M"
//   987654321 -> "987.6M"
String fmtCompact(num v) {
  final sign = v < 0 ? '-' : '';
  double n = v.abs().toDouble();
  const units = ['', 'K', 'M', 'B', 'T', 'P', 'E'];
  int i = 0;
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000;
    i++;
  }

  String s;
  if (n >= 100) {
    // 100+ → integer only
    s = n.toStringAsFixed(0);
  } else {
    // <100 → 1 decimal place, truncated (not rounded)
    final truncated = _truncateTo(n, 1);
    s = truncated.toStringAsFixed(1);
    s = _stripTrailingZeros(s);
  }

  return '$sign$s${units[i]}';
}

// Tight formatter for small values, strips trailing zeros intelligently.
// Examples:
//   0.30 -> "0.3"
//   1.50 -> "1.5"
//   2.00 -> "2"
//   1.45 -> "1.45"
String fmtTight(num v, {int maxDecimals = 3}) {
  String s = v.toStringAsFixed(maxDecimals);
  return _stripTrailingZeros(s);
}

// Hybrid: compact for large values, tight for small values
String fmtSmart(num v) {
  if (v.abs() >= 1000) return fmtCompact(v);
  return fmtTight(v);
}

// Whole-number currency formatter (no decimals anywhere).
// For large values, uses compact units *without* decimals (e.g., 1K, 2M).
String fmtCurrencyWhole(num v) {
  final sign = v < 0 ? '-' : '';
  double n = v.abs().toDouble();
  const units = ['', 'K', 'M', 'B', 'T', 'P', 'E'];
  int i = 0;
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000;
    i++;
  }
  final s = n.toStringAsFixed(0);
  return '$sign$s${units[i]}';
}

// General number formatter (for tap/rate values).
// - Integers shown without decimals (e.g., 1)
// - Otherwise show up to [maxDecimals] with no trailing zeros
// Examples:
//   1.0   -> "1"
//   1.25  -> "1.25"
//   1.3   -> "1.3"
//   1.300 -> "1.3"
String fmtNumber(num v, {int maxDecimals = 6}) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) {
    return d.toInt().toString();
  }
  return _stripTrailingZeros(d.toStringAsFixed(maxDecimals));
}
