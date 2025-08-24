// lib/utils/format.dart

// Compact number formatter for game values.
// Example:
//   50       -> "50"
//   5000     -> "5K"
//   5500000  -> "5.5M"
//   987654321 -> "987.65M" (2 decimals under 10B, 1 decimal after)
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
    s = n.toStringAsFixed(0);
  } else if (n >= 10) {
    s = n.toStringAsFixed(1);
  } else {
    s = n.toStringAsFixed(2);
  }

  // remove trailing .0
  if (s.endsWith('.0')) {
    s = s.substring(0, s.length - 2);
  }

  return '$sign$s${units[i]}';
}
