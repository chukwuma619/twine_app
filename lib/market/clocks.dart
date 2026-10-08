String remainingLabel(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  if (left.isNegative || left.inSeconds == 0) return 'Time is up';
  final hours = left.inHours;
  final minutes = left.inMinutes.remainder(60);
  final seconds = left.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m left';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s left';
  }
  return '${seconds}s left';
}

DateTime? unixSeconds(Object? value) {
  final int? seconds;
  if (value is int) {
    seconds = value;
  } else if (value is num) {
    seconds = value.toInt();
  } else if (value is String) {
    seconds = int.tryParse(value.trim());
  } else {
    seconds = null;
  }
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

int? unixJson(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
