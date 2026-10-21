import 'dart:convert';

final class CrashReportUtils._() {
  static String formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  /// An `.ips` report — a JSON header line, then a JSON body — with both
  /// parts indented, or null when [content] isn't one (a `.crash` report).
  static String? prettyIps(String content) {
    final newline = content.indexOf('\n');
    if (newline < 0) return null;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final header = jsonDecode(content.substring(0, newline));
      final body = jsonDecode(content.substring(newline + 1));
      return '${encoder.convert(header)}\n${encoder.convert(body)}';
    } on FormatException {
      return null;
    }
  }
}
