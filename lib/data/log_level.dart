/// A single source of truth for log-level metadata used across Android
/// (logcat) and iOS (syslog / os_log) streams.
///
/// [code] is a shared canonical identifier used by settings and filtering.
/// Raw log-entry values can still differ per platform (`E`, `W`, `debug`, ...)
/// and are resolved back to one of these shared levels when needed.
class LogLevel {
  const LogLevel._({
    required this.code,
    required this.label,
    required this.hierarchy,
    this.isUnknown = false,
  });

  final String code;
  final String label;

  /// Lower number = higher priority.
  final int hierarchy;

  /// `true` when this instance represents an unrecognised raw value.
  final bool isUnknown;

  static const unknown = LogLevel._(
    code: 'unknown',
    label: 'Unknown',
    hierarchy: 0,
    isUnknown: true,
  );

  static const fault = LogLevel._(code: 'fault', label: 'Fault', hierarchy: 1);

  static const error = LogLevel._(code: 'error', label: 'Error', hierarchy: 2);

  static const warning = LogLevel._(
    code: 'warning',
    label: 'Warning',
    hierarchy: 3,
  );

  static const defaultLevel = LogLevel._(
    code: 'default',
    label: 'Default',
    hierarchy: 4,
  );

  static const info = LogLevel._(code: 'info', label: 'Info', hierarchy: 5);

  static const debug = LogLevel._(code: 'debug', label: 'Debug', hierarchy: 6);

  static const verbose = LogLevel._(
    code: 'verbose',
    label: 'Verbose',
    hierarchy: 7,
  );

  static const List<LogLevel> values = [
    unknown,
    fault,
    error,
    warning,
    defaultLevel,
    info,
    debug,
    verbose,
  ];

  /// Shared levels available in Android-focused UI.
  static const List<LogLevel> androidValues = [
    error,
    warning,
    info,
    debug,
    verbose,
  ];

  /// Shared levels available in iOS-focused UI.
  static const List<LogLevel> iosValues = [
    unknown,
    fault,
    error,
    defaultLevel,
    info,
    debug,
  ];

  static LogLevel fromStored(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return unknown;

    final lower = trimmed.toLowerCase();
    final upper = trimmed.toUpperCase();

    switch (lower) {
      case 'unknown':
        return unknown;
      case 'fault':
      case 'critical':
        return fault;
      case 'error':
        return error;
      case 'warning':
      case 'warn':
        return warning;
      case 'default':
      case 'notice':
        return defaultLevel;
      case 'info':
        return info;
      case 'debug':
        return debug;
      case 'verbose':
        return verbose;
      case 'fatal':
      case 'assert':
        return fault;
    }

    switch (upper) {
      case 'F':
      case 'A':
        return fault;
      case 'E':
        return error;
      case 'W':
        return warning;
      case 'I':
        return info;
      case 'D':
        return debug;
      case 'V':
        return verbose;
    }

    return LogLevel._(
      code: trimmed,
      label: 'Unknown',
      hierarchy: unknown.hierarchy,
      isUnknown: true,
    );
  }

  static LogLevel fromAndroidCode(String code) => fromStored(code);

  static LogLevel fromAndroidName(String name) => fromStored(name);

  static LogLevel fromIosRaw(String raw) => fromStored(raw);

  static String normalizeAndroidStoredLevel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return verbose.androidCode;

    final level = fromStored(trimmed);
    final normalizedUpper = trimmed.toUpperCase();
    final normalizedLower = trimmed.toLowerCase();
    final isKnownAndroidValue = switch (normalizedUpper) {
      'F' || 'A' || 'E' || 'W' || 'I' || 'D' || 'V' => true,
      _ => switch (normalizedLower) {
        'fatal' ||
        'assert' ||
        'error' ||
        'warn' ||
        'warning' ||
        'info' ||
        'debug' ||
        'verbose' => true,
        _ => false,
      },
    };

    return isKnownAndroidValue ? level.androidCode : trimmed;
  }

  static String normalizeIosStoredLevel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return unknown.code;

    final normalizedLower = trimmed.toLowerCase();
    return switch (normalizedLower) {
      'fault' || 'critical' => fault.code,
      'error' => error.code,
      'warning' || 'warn' => warning.code,
      'default' || 'notice' => defaultLevel.code,
      'info' => info.code,
      'debug' => debug.code,
      'unknown' => unknown.code,
      _ => trimmed.toLowerCase(),
    };
  }

  static bool looksLikeIosStoredLevel(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'unknown' ||
      'fault' ||
      'critical' ||
      'error' ||
      'warning' ||
      'warn' ||
      'default' ||
      'notice' ||
      'info' ||
      'debug' => true,
      _ => false,
    };
  }

  static LogLevel defaultSelectionForPlatform({required bool isIos}) =>
      isIos ? debug : verbose;

  LogLevel normalizeSelectionForPlatform({required bool isIos}) {
    final supportedValues = isIos ? iosValues : androidValues;
    if (supportedValues.contains(this) && !isUnknown) {
      return this;
    }
    if (isUnknown) {
      return defaultSelectionForPlatform(isIos: isIos);
    }

    return supportedValues.firstWhere(
      (level) => level.hierarchy >= hierarchy,
      orElse: () => supportedValues.last,
    );
  }

  String get androidCode => switch (code) {
    'fault' => 'F',
    'error' => 'E',
    'warning' => 'W',
    'default' || 'info' => 'I',
    'debug' => 'D',
    'verbose' => 'V',
    'unknown' => '?',
    _ => code.toUpperCase(),
  };

  String displayCode({required bool isIos}) => isIos ? code : androidCode;

  String labelWithDisplayCode({required bool isIos}) =>
      '$label (${displayCode(isIos: isIos)})';

  String get labelWithCode => '$label ($code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LogLevel && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'LogLevel($code)';
}
