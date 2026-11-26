import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onPoll] every [interval] while the app is in the foreground, and once with
/// `force: true` when it comes back, so screens are fresh as soon as they're visible.
/// Whether a tick actually hits the network is up to [onPoll].
class ForegroundPoller {
  ForegroundPoller({required this.interval, required this.onPoll});

  final Duration interval;
  final void Function({required bool force}) onPoll;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;

  void start() {
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        onPoll(force: true);
      },
      onHide: () => _foreground = false,
    );
    _timer = Timer.periodic(interval, (_) {
      if (_foreground) onPoll(force: false);
    });
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }
}
