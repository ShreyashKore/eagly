import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/log_column.dart';
import '../data/log_tab_settings.dart';
import '../data/log_view_mode.dart';

extension SharedPreferencesJson on SharedPreferences {
  /// Reads a JSON-encoded value from persistent storage and decodes it.
  /// Returns `null` if the key doesn't exist or decoding fails.
  T? getJson<T>(String key, T Function(dynamic json) fromJson) {
    final raw = getString(key);
    if (raw == null) return null;
    return fromJson(jsonDecode(raw));
  }

  /// JSON-encodes [value] and saves it to persistent storage.
  Future<bool> setJson(String key, Object value) =>
      setString(key, jsonEncode(value));
}

class PreferencesService {
  static late SharedPreferences _prefs;
  static final ValueNotifier<ThemeMode> themeModeListenable = ValueNotifier(
    ThemeMode.dark,
  );

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    themeModeListenable.value = themeMode;
  }

  // Keys
  static const _keyWrapText = 'wrapText';
  static const _keyAutoScroll = 'autoScroll';
  static const _keyViewMode = 'viewMode';
  static const _keySelectedLogLevel = 'selectedLogLevel';
  static const _keyColumnWidths = 'columnWidths';
  static const _keyHiddenColumns = 'hiddenColumns';
  static const _keyLogLinesLimit = 'logLinesLimit';
  static const _keyThemeMode = 'themeMode';
  static const _keyLastFileDialogDirectory = 'lastFileDialogDirectory';

  // --- Home page preferences ---

  static bool get wrapText => _prefs.getBool(_keyWrapText) ?? false;
  static set wrapText(bool v) => _prefs.setBool(_keyWrapText, v);

  static bool get autoScroll => _prefs.getBool(_keyAutoScroll) ?? true;
  static set autoScroll(bool v) => _prefs.setBool(_keyAutoScroll, v);

  static LogViewMode get viewMode => LogViewMode.values.firstWhere(
    (m) => m.name == _prefs.getString(_keyViewMode),
    orElse: () => LogViewMode.text,
  );

  static set viewMode(LogViewMode v) => _prefs.setString(_keyViewMode, v.name);

  static String get selectedLogLevel =>
      _prefs.getString(_keySelectedLogLevel) ?? 'V';
  static set selectedLogLevel(String v) =>
      _prefs.setString(_keySelectedLogLevel, v);

  static int get logLinesLimit => _prefs.getInt(_keyLogLinesLimit) ?? 50000;
  static set logLinesLimit(int v) => _prefs.setInt(_keyLogLinesLimit, v);

  static ThemeMode get themeMode =>
      _themeModeFromName(_prefs.getString(_keyThemeMode)) ?? ThemeMode.dark;

  static String? get lastFileDialogDirectory =>
      _prefs.getString(_keyLastFileDialogDirectory);

  static Future<bool> setLastFileDialogDirectory(String? value) {
    if (value == null || value.isEmpty) {
      return _prefs.remove(_keyLastFileDialogDirectory);
    }

    return _prefs.setString(_keyLastFileDialogDirectory, value);
  }

  static set themeMode(ThemeMode value) {
    themeModeListenable.value = value;
    _prefs.setString(_keyThemeMode, value.name);
  }

  static LogTabSettings get defaultTabSettings => LogTabSettings(
    wrapText: wrapText,
    autoScroll: autoScroll,
    selectedLogLevel: selectedLogLevel,
    viewMode: viewMode,
    logLinesLimit: logLinesLimit,
    hiddenColumns: hiddenColumns,
    columnWidths: columnWidths,
  );

  // --- Column widths (stored as single JSON object) ---

  static Map<String, double> get columnWidths {
    final defaults = {for (final c in LogColumn.values) c.name: c.defaultWidth};
    return _prefs.getJson<Map<String, double>>(
          _keyColumnWidths,
          (json) => (json as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ) ??
        defaults;
  }

  static set columnWidths(Map<String, double> v) =>
      _prefs.setJson(_keyColumnWidths, v);

  // --- Hidden columns (stored as JSON list of column names) ---

  static Set<String> get hiddenColumns {
    return _prefs.getJson<Set<String>>(
          _keyHiddenColumns,
          (json) => (json as List<dynamic>).map((e) => e as String).toSet(),
        ) ??
        {};
  }

  static set hiddenColumns(Set<String> v) =>
      _prefs.setJson(_keyHiddenColumns, v.toList());

  static ThemeMode? _themeModeFromName(String? value) {
    return switch (value) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }
}
