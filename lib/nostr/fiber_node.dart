import 'dart:convert';

class FiberAnnouncement {
  const FiberAnnouncement({
    required this.pubkey,
    required this.hasSolverField,
    this.solver,
    this.solverWindowSecs,
    this.addresses = const [],
  });

  final String pubkey;
  final bool hasSolverField;
  final String? solver;
  final int? solverWindowSecs;
  final List<String> addresses;

  bool get solverConfigured => solver != null && solver!.isNotEmpty;

  static FiberAnnouncement? fromContent(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = decoded.map((key, item) => MapEntry('$key', item));
    final pubkey = map['pubkey'];
    if (pubkey is! String || pubkey.trim().isEmpty) return null;
    final hasSolverField = map.containsKey('solver');
    final rawSolver = map['solver'];
    final String? solver;
    if (rawSolver is String && rawSolver.trim().isNotEmpty) {
      solver = rawSolver.trim();
    } else {
      solver = null;
    }
    final rawWindow = map['solver_window_secs'];
    final int? solverWindowSecs;
    if (rawWindow is int) {
      solverWindowSecs = rawWindow;
    } else if (rawWindow is num) {
      solverWindowSecs = rawWindow.toInt();
    } else {
      solverWindowSecs = null;
    }
    final rawAddresses = map['addresses'];
    final addresses = [
      if (rawAddresses is List)
        for (final item in rawAddresses)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    return FiberAnnouncement(
      pubkey: pubkey.trim(),
      hasSolverField: hasSolverField,
      solver: solver,
      solverWindowSecs: solverWindowSecs,
      addresses: addresses,
    );
  }
}

String? openFiberNode(String content) {
  return FiberAnnouncement.fromContent(content)?.pubkey;
}
