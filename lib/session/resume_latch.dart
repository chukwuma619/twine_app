import 'package:flutter/widgets.dart';

/// How long a resume waits before dialing, so a flapping transition runs once.
const resumeDebounce = Duration(milliseconds: 300);

/// Remembers a real suspension.
///
/// Unlocking the screen is `paused → inactive → resumed`. The state right
/// before `resumed` is `inactive`, so comparing only the previous state never
/// sees the return. `inactive` does not arm or clear this latch.
class ResumeLatch {
  bool _suspended = false;

  bool get suspended => _suspended;

  /// True when [state] is the resume that ends a suspension.
  bool observe(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _suspended = true;
        return false;
      case AppLifecycleState.resumed:
        if (!_suspended) return false;
        _suspended = false;
        return true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        return false;
    }
  }
}
