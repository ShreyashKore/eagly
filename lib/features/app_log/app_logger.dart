import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Severity level of an [AppLogEntry].
enum AppLogLevel { debug, info, success, warning, error }

/// A single structured log entry produced by the app itself (not device logs).
class AppLogEntry {
  AppLogEntry({
    required this.level,
    required this.source,
    required this.message,
    this.detail,
    this.sessionTag,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final AppLogLevel level;
  final String source;
  final String message;
  final String? detail;
  final String? sessionTag;
  final DateTime timestamp;

  String toExportString() {
    final buf = StringBuffer();
    buf.write('[${_formatTimestamp(timestamp)}]');
    buf.write(' ${level.name.toUpperCase().padRight(7)}');
    buf.write(' [$source]');
    if (sessionTag != null) buf.write(' {$sessionTag}');
    buf.write('  $message');
    if (detail != null && detail!.isNotEmpty) {
      buf.write('\n    ${detail!.replaceAll('\n', '\n    ')}');
    }
    return buf.toString();
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// Composable app-internal logger.
///
/// Every instance writes to the same root in-memory store, but instances can be
/// created with default [source] and/or [sessionTag] values for a feature,
/// service, or workspace session.
class AppLogger {
  AppLogger({String? source, String? sessionTag})
    : _defaultSource = source,
      _defaultSessionTag = sessionTag;

  static final AppLogger global = AppLogger();
  static const int maxEntries = 2000;

  final _AppLogStore _store = _AppLogStore.instance;
  final String? _defaultSource;
  final String? _defaultSessionTag;

  ChangeNotifier get entriesListenable => _store;

  List<AppLogEntry> get entries => List.unmodifiable(_store.entries);

  AppLogger scoped({String? source, String? sessionTag}) {
    return AppLogger(
      source: source ?? _defaultSource,
      sessionTag: sessionTag ?? _defaultSessionTag,
    );
  }

  AppLogEntry? latestEntry({String? sessionTag, bool errorsOnly = false}) {
    for (final entry in _store.entries.toList(growable: false).reversed) {
      if (sessionTag != null && entry.sessionTag != sessionTag) {
        continue;
      }
      if (errorsOnly && entry.level != AppLogLevel.error) {
        continue;
      }
      return entry;
    }
    return null;
  }

  bool hasEntries({String? sessionTag, bool errorsOnly = false}) {
    return _store.entries.any((entry) {
      if (sessionTag != null && entry.sessionTag != sessionTag) {
        return false;
      }
      if (errorsOnly && entry.level != AppLogLevel.error) {
        return false;
      }
      return true;
    });
  }

  List<AppLogEntry> entriesWhere({
    String? sessionTag,
    bool errorsOnly = false,
  }) {
    final filtered = _store.entries
        .where((entry) {
          if (sessionTag != null && entry.sessionTag != sessionTag) {
            return false;
          }
          if (errorsOnly && entry.level != AppLogLevel.error) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    return List.unmodifiable(filtered);
  }

  List<AppLogEntry> entriesForSession(String? sessionTag) =>
      entriesWhere(sessionTag: sessionTag);

  String exportAll() => exportEntries(entries);

  String exportEntries(Iterable<AppLogEntry> values) =>
      values.map((e) => e.toExportString()).join('\n');

  void clear() {
    _store.clear();
  }

  void debug(
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) => _submit(
    AppLogLevel.debug,
    message,
    detail: detail,
    source: source,
    sessionTag: sessionTag,
  );

  void info(
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) => _submit(
    AppLogLevel.info,
    message,
    detail: detail,
    source: source,
    sessionTag: sessionTag,
  );

  void success(
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) => _submit(
    AppLogLevel.success,
    message,
    detail: detail,
    source: source,
    sessionTag: sessionTag,
  );

  void warning(
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) => _submit(
    AppLogLevel.warning,
    message,
    detail: detail,
    source: source,
    sessionTag: sessionTag,
  );

  void error(
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) => _submit(
    AppLogLevel.error,
    message,
    detail: detail,
    source: source,
    sessionTag: sessionTag,
  );

  void _submit(
    AppLogLevel level,
    String message, {
    String? detail,
    String? source,
    String? sessionTag,
  }) {
    _store.add(
      AppLogEntry(
        level: level,
        source: source ?? _defaultSource ?? 'App',
        message: message,
        detail: detail,
        sessionTag: sessionTag ?? _defaultSessionTag,
      ),
    );
  }
}

class _AppLogStore extends ChangeNotifier {
  _AppLogStore._();

  static final _AppLogStore instance = _AppLogStore._();

  final ListQueue<AppLogEntry> entries = ListQueue<AppLogEntry>();

  void add(AppLogEntry entry) {
    if (entries.length >= AppLogger.maxEntries) {
      entries.removeFirst();
    }
    entries.addLast(entry);
    if (kDebugMode) {
      // ignore: avoid_print
      print(entry.toExportString());
    }
    notifyListeners();
  }

  void clear() {
    entries.clear();
    notifyListeners();
  }
}

