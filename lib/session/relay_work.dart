/// One relay pass at a time.
///
/// A resume that arrives during a probe runs after that probe. A resume that
/// arrives during a redial is remembered and runs once the redial finishes,
/// so the return from sleep is not dropped and two dials do not run at once.
class RelayWork {
  Future<void>? _current;
  bool _again = false;

  /// A resume arrived while a pass is already running.
  bool get replaceQueued => _again;

  Future<void> run({
    required bool replace,
    required Future<void> Function(bool replace) body,
  }) {
    final current = _current;
    if (current != null) {
      if (replace) _again = true;
      return current;
    }
    final run = _drain(replace, body);
    _current = run;
    return run.whenComplete(() {
      if (identical(_current, run)) _current = null;
    });
  }

  Future<void> _drain(
    bool replace,
    Future<void> Function(bool replace) body,
  ) async {
    await body(replace);
    while (_again) {
      _again = false;
      await body(true);
    }
  }
}
