class TimestampUtils {
  /// Convert Unix timestamp (seconds + nanoseconds) to readable format
  static String formatTimestamp(int seconds, int nanos) {
    if (seconds == 0) return '';

    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + (nanos ~/ 1000000),
      isUtc: false,
    );

    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final millisecond = dateTime.millisecond.toString().padLeft(3, '0');

    return '$year-$month-$day $hour:$minute:$second.$millisecond';
  }

  /// Parse readable timestamp back to seconds/nanos format
  static Map<String, int> parseTimestampToSecondsNanos(String timestamp) {
    if (timestamp.isEmpty) {
      return {'seconds': 0, 'nanos': 0};
    }

    try {
      final parts = timestamp.split(' ');
      if (parts.length != 2) return {'seconds': 0, 'nanos': 0};

      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');

      if (dateParts.length != 3 || timeParts.length != 3) {
        return {'seconds': 0, 'nanos': 0};
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final secondParts = timeParts[2].split('.');
      final second = int.parse(secondParts[0]);
      final millisecond = secondParts.length > 1 ? int.parse(secondParts[1]) : 0;

      final dateTime = DateTime(year, month, day, hour, minute, second, millisecond);
      final millisecondsSinceEpoch = dateTime.millisecondsSinceEpoch;

      final seconds = millisecondsSinceEpoch ~/ 1000;
      final nanos = (millisecondsSinceEpoch % 1000) * 1000000;

      return {'seconds': seconds, 'nanos': nanos};
    } catch (e) {
      return {'seconds': 0, 'nanos': 0};
    }
  }
}
