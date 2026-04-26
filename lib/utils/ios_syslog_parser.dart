import 'dart:convert';

import '../data/log_entry.dart';
import '../data/log_level.dart';

class IosSyslogParser {
  IosSyslogParser({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final RegExp _metaEscapePattern = RegExp(r'\\M(?:-|\^|.)');

  static final RegExp _headerPattern = RegExp(
    r'^([A-Z][a-z]{2}\s+\d{1,2}\s+\d\d:\d\d:\d\d(?:\.\d+)?)\s+(.+?)\[(\d+)\]\s+<([^>]+)>:\s?(.*)$',
  );

  static const Map<String, int> _monthNumbers = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  final DateTime Function() _now;
  _IosSyslogEntryBuilder? _currentEntry;

  Iterable<LogEntry> addLine(String line) sync* {
    final normalizedLine = _decodeMetaEscapes(line);
    final parsedHeader = _IosSyslogEntryBuilder.tryParse(
      normalizedLine,
      now: _now,
    );
    if (parsedHeader != null) {
      final previousEntry = _currentEntry?.build();
      _currentEntry = parsedHeader;
      if (previousEntry != null) {
        yield previousEntry;
      }
      return;
    }

    _currentEntry?.appendContinuation(normalizedLine);
  }

  LogEntry? flush() {
    final entry = _currentEntry?.build();
    _currentEntry = null;
    return entry;
  }

  static String? normalizeTimestamp(
    String rawTimestamp, {
    DateTime Function()? now,
  }) {
    final match = RegExp(
      r'^([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d\d):(\d\d):(\d\d)(?:\.(\d+))?$',
    ).firstMatch(rawTimestamp.trim());
    if (match == null) {
      return null;
    }

    final month = _monthNumbers[match.group(1)!];
    if (month == null) {
      return null;
    }

    final currentTime = (now ?? DateTime.now)();

    try {
      final day = int.parse(match.group(2)!);
      final hour = int.parse(match.group(3)!);
      final minute = int.parse(match.group(4)!);
      final second = int.parse(match.group(5)!);
      final fractionalPart = match.group(6) ?? '';
      final paddedFraction = fractionalPart.padRight(6, '0');
      final microseconds = paddedFraction.isEmpty
          ? 0
          : int.parse(paddedFraction.substring(0, 6));

      final timestamp = DateTime(
        currentTime.year,
        month,
        day,
        hour,
        minute,
        second,
        microseconds ~/ 1000,
        microseconds % 1000,
      );

      final year = timestamp.year.toString().padLeft(4, '0');
      final monthText = timestamp.month.toString().padLeft(2, '0');
      final dayText = timestamp.day.toString().padLeft(2, '0');
      final hourText = timestamp.hour.toString().padLeft(2, '0');
      final minuteText = timestamp.minute.toString().padLeft(2, '0');
      final secondText = timestamp.second.toString().padLeft(2, '0');
      final millisecondText = timestamp.millisecond.toString().padLeft(3, '0');
      return '$year-$monthText-$dayText $hourText:$minuteText:$secondText.$millisecondText';
    } catch (_) {
      return null;
    }
  }

  /// Temporary workaround to decode special characters
  static String _decodeMetaEscapes(String line) {
    if (!_metaEscapePattern.hasMatch(line)) {
      return line;
    }

    final bytes = <int>[];
    var changed = false;
    var index = 0;

    while (index < line.length) {
      if (line.startsWith(r'\M', index)) {
        final decoded = _decodeMetaEscapeToken(line, index);
        if (decoded != null) {
          bytes.add(decoded.byte);
          index = decoded.nextIndex;
          changed = true;
          continue;
        }
      }

      final codeUnit = line.codeUnitAt(index);
      if (codeUnit > 0x7f) {
        return line;
      }
      bytes.add(codeUnit);
      index += 1;
    }

    if (!changed) {
      return line;
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {
      return line;
    }
  }

  static _DecodedMetaEscape? _decodeMetaEscapeToken(String line, int index) {
    var current = index + 2;
    if (current >= line.length) {
      return null;
    }

    if (line.codeUnitAt(current) == 0x2d) {
      current += 1;
      if (current >= line.length) {
        return null;
      }
    }

    if (line.codeUnitAt(current) == 0x5e) {
      if (current + 1 >= line.length) {
        return null;
      }
      final control = line.codeUnitAt(current + 1);
      return _DecodedMetaEscape(0x80 | (control & 0x1f), current + 2);
    }

    return _DecodedMetaEscape(0x80 | line.codeUnitAt(current), current + 1);
  }
}

class _DecodedMetaEscape {
  const _DecodedMetaEscape(this.byte, this.nextIndex);

  final int byte;
  final int nextIndex;
}

class _IosSyslogEntryBuilder {
  _IosSyslogEntryBuilder({
    required this.timestamp,
    required this.processLabel,
    required this.pid,
    required this.level,
    required String message,
  }) : _message = StringBuffer(message);

  final String timestamp;
  final String processLabel;
  final String pid;
  final String level;
  final StringBuffer _message;

  static _IosSyslogEntryBuilder? tryParse(
    String line, {
    required DateTime Function() now,
  }) {
    final match = IosSyslogParser._headerPattern.firstMatch(line);
    if (match == null) {
      return null;
    }

    final normalizedTimestamp = IosSyslogParser.normalizeTimestamp(
      match.group(1)!,
      now: now,
    );
    if (normalizedTimestamp == null) {
      return null;
    }

    return _IosSyslogEntryBuilder(
      timestamp: normalizedTimestamp,
      processLabel: match.group(2)!.trim(),
      pid: match.group(3)!,
      level: _mapLevel(match.group(4)!),
      message: match.group(5) ?? '',
    );
  }

  static String _mapLevel(String rawLevel) =>
      LogLevel.normalizeIosStoredLevel(rawLevel);

  void appendContinuation(String line) {
    _message.writeln();
    _message.write(line);
  }

  LogEntry build() {
    final processName = _compactProcessName(processLabel);
    return LogEntry(
      timestamp: timestamp,
      pid: pid,
      tid: '0',
      level: level,
      tag: processLabel,
      message: _message.toString(),
      packageName: processName,
      processName: processLabel,
    );
  }

  String _compactProcessName(String rawLabel) {
    final separatorIndex = rawLabel.indexOf('(');
    final compact = separatorIndex < 0
        ? rawLabel.trim()
        : rawLabel.substring(0, separatorIndex).trim();
    return compact.isEmpty ? rawLabel.trim() : compact;
  }
}
