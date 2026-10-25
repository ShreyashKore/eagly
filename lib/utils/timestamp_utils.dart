/// How much of the time of day [formatDateTime] and [formatTimeOfDay] write.
enum TimePrecision { minute, second, millisecond }

String _two(int value) => value.toString().padLeft(2, '0');

/// `14:03:07.250` in local time, down to [precision].
String formatTimeOfDay(
  DateTime time, {
  TimePrecision precision = TimePrecision.millisecond,
}) {
  final local = time.toLocal();
  final buffer = StringBuffer('${_two(local.hour)}:${_two(local.minute)}');
  if (precision != TimePrecision.minute) buffer.write(':${_two(local.second)}');
  if (precision == TimePrecision.millisecond) {
    buffer.write('.${local.millisecond.toString().padLeft(3, '0')}');
  }
  return buffer.toString();
}

/// `2026-10-25 14:03:07.250` in local time, down to [precision].
String formatDateTime(
  DateTime time, {
  TimePrecision precision = TimePrecision.millisecond,
}) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${formatTimeOfDay(local, precision: precision)}';
}

/// `20261025-140307`, local time: a timestamp safe in a file name.
String fileNameTimestamp(DateTime time) {
  final local = time.toLocal();
  return '${local.year}${_two(local.month)}${_two(local.day)}-'
      '${_two(local.hour)}${_two(local.minute)}${_two(local.second)}';
}

class TimestampUtils {
  /// Convert Unix timestamp (seconds + nanoseconds) to readable format
  static String formatTimestamp(int seconds, int nanos) {
    if (seconds == 0) return '';

    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + (nanos ~/ 1000000),
      isUtc: false,
    );

    return formatDateTime(dateTime);
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

      if (dateParts.length < 2 || timeParts.length != 3) {
        return {'seconds': 0, 'nanos': 0};
      }

      final int? year;
      final int month;
      final int day;
      if (dateParts.length == 3) {
        year = int.parse(dateParts[0]);
        month = int.parse(dateParts[1]);
        day = int.parse(dateParts[2]);
      } else {
        year = null;
        month = int.parse(dateParts[0]);
        day = int.parse(dateParts[1]);
      }
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final secondParts = timeParts[2].split('.');
      final second = int.parse(secondParts[0]);
      final millisecond = secondParts.length > 1
          ? int.parse(secondParts[1])
          : 0;

      final dateTime = DateTime(
        year ?? DateTime.now().year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
      );
      final millisecondsSinceEpoch = dateTime.millisecondsSinceEpoch;

      final seconds = millisecondsSinceEpoch ~/ 1000;
      final nanos = (millisecondsSinceEpoch % 1000) * 1000000;

      return {'seconds': seconds, 'nanos': nanos};
    } catch (e) {
      return {'seconds': 0, 'nanos': 0};
    }
  }
}
