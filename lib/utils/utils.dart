import 'dart:convert';
import 'dart:io';

/// Reads [file] as UTF-8 text, tolerating malformed byte sequences (replaced
/// with U+FFFD) rather than throwing. iOS `.ips` reports are normally UTF-8/JSON
/// but some diagnostic ones (e.g. WiFiLQMMetrics) embed non-UTF-8 bytes that
/// strict decoding rejects.
Future<String> readTextLenient(File file) =>
    file.readAsString(encoding: const Utf8Codec(allowMalformed: true));

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final precision = value >= 100 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

String describeError(Object error) {
  if (error is FormatException) {
    return error.message;
  }

  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}

String extractFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? path : segments.last;
}

int parseIntOrZero(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
