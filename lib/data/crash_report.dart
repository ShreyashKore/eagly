import 'dart:convert';

/// A single crash report copied off an iOS device by `idevicecrashreport`.
///
/// Modern iOS reports are `.ips` files whose first line is a small JSON header
/// (app name, timestamp, …); older reports are plain-text `.crash` files with a
/// `Process:` / `Date/Time:` preamble. [CrashReport.fromFile] parses either,
/// falling back to the filename and the file's modified time when metadata is
/// missing.
class CrashReport {
  const CrashReport({
    required this.fileName,
    required this.filePath,
    required this.processName,
    required this.timestamp,
    required this.sizeBytes,
  });

  final String fileName;
  final String filePath;

  /// Best-effort name of the process/app that crashed.
  final String processName;

  /// When the crash occurred, best-effort. Falls back to the file mtime.
  final DateTime timestamp;
  final int sizeBytes;

  /// Builds a report from a copied crash file. [content] is the raw file text
  /// and [modified] the file's last-modified time (used as a timestamp
  /// fallback).
  factory CrashReport.fromFile({
    required String fileName,
    required String filePath,
    required String content,
    required DateTime modified,
    required int sizeBytes,
  }) {
    final isIps = fileName.toLowerCase().endsWith('.ips');
    final header = isIps
        ? _parseIpsHeader(content)
        : _parseCrashHeader(content);

    final processName =
        header.processName ??
        _processNameFromFileName(fileName) ??
        'Unknown app';
    final timestamp =
        header.timestamp ?? _timestampFromFileName(fileName) ?? modified;

    return CrashReport(
      fileName: fileName,
      filePath: filePath,
      processName: processName,
      timestamp: timestamp,
      sizeBytes: sizeBytes,
    );
  }

  static _CrashHeader _parseIpsHeader(String content) {
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return const _CrashHeader();
    try {
      final decoded = jsonDecode(firstLine);
      if (decoded is! Map<String, dynamic>) return const _CrashHeader();
      final name =
          decoded['app_name'] ?? decoded['name'] ?? decoded['procName'];
      final rawTimestamp = decoded['timestamp'];
      return _CrashHeader(
        processName: name is String && name.trim().isNotEmpty
            ? name.trim()
            : null,
        timestamp: rawTimestamp is String
            ? _tryParseAppleDate(rawTimestamp)
            : null,
      );
    } catch (_) {
      return const _CrashHeader();
    }
  }

  static _CrashHeader _parseCrashHeader(String content) {
    String? processName;
    DateTime? timestamp;
    for (final line in const LineSplitter().convert(content)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (value.isEmpty) continue;
      if (processName == null && (key == 'Process' || key == 'Name')) {
        // e.g. "Process: MyApp [1234]"
        final bracket = value.indexOf('[');
        processName = (bracket > 0 ? value.substring(0, bracket) : value).trim();
      } else if (timestamp == null && key == 'Date/Time') {
        timestamp = _tryParseAppleDate(value);
      }
      if (processName != null && timestamp != null) break;
    }
    return _CrashHeader(processName: processName, timestamp: timestamp);
  }

  /// Parses the `<ProcessName>-<YYYY-MM-DD-HHMMSS>.ext` filename convention.
  static String? _processNameFromFileName(String fileName) {
    final match = _fileNamePattern.firstMatch(fileName);
    final name = match?.group(1)?.trim();
    return (name != null && name.isNotEmpty) ? name : null;
  }

  static DateTime? _timestampFromFileName(String fileName) {
    final match = _fileNamePattern.firstMatch(fileName);
    if (match == null) return null;
    return DateTime.tryParse(
      '${match.group(2)}-${match.group(3)}-${match.group(4)}'
      'T${match.group(5)}:${match.group(6)}:${match.group(7)}',
    );
  }

  /// Apple timestamps look like `2024-06-09 12:00:00.000 +0000`. Normalize the
  /// space separator so [DateTime.tryParse] accepts it.
  static DateTime? _tryParseAppleDate(String value) {
    final normalized = value.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  static final RegExp _fileNamePattern = RegExp(
    r'^(.*)-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})\.[^.]+$',
  );
}

class _CrashHeader {
  const _CrashHeader({this.processName, this.timestamp});

  final String? processName;
  final DateTime? timestamp;
}
