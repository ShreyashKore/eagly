final class CrashReportUtils {
  CrashReportUtils._();
  static String formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
