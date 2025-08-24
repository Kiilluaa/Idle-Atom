// lib/utils/debouncer.dart
import 'dart:async';

/// Simple Debouncer utility to throttle actions (e.g., save notifications).
class Debouncer {
  Debouncer({required this.duration});
  final Duration duration;

  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
