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

/// The first of [first] and [second] with any non-blank text, trimmed.
String? firstNonBlank(String? first, [String? second]) {
  for (final value in [first, second]) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// `Key: value` lines — `ideviceinfo`, `dumpsys` — as a map, both sides
/// trimmed. Lines without a key or a value are skipped.
Map<String, String> parseColonSeparated(String output) {
  final values = <String, String>{};
  for (final line in output.split('\n')) {
    final separatorIndex = line.indexOf(':');
    if (separatorIndex <= 0) continue;
    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    values[key] = value;
  }
  return values;
}

/// "1 file", "3 files": [count] and [noun], plural unless [count] is 1.
/// [plural] covers nouns that don't just take an "s".
String pluralize(int count, String noun, {String? plural}) =>
    '$count ${count == 1 ? noun : plural ?? '${noun}s'}';

/// Single-quotes [value] for a POSIX shell — usually the *device's* `sh` —
/// so spaces and metacharacters can't break out of the command being built.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
