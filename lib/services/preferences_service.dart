import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/apps/data/apps_view_options.dart';
import '../features/logs/data/models/log_column.dart';
import '../features/logs/data/models/log_level.dart';
import '../features/logs/data/models/log_tab_settings.dart';

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
    logFontSizeListenable.value = logFontSize;
    recentLogFilesListenable.value = recentLogFiles;
    tipsEnabledListenable.value = tipsEnabled;
    zoomLevelListenable.value = zoomLevel;
    _removeRetiredKeys();
  }

  /// Keys earlier versions stored that nothing reads any more.
  static const _retiredKeys = [
    'filterViewMode', // The pill filter bar is the only one now.
  ];

  static void _removeRetiredKeys() {
    for (final key in _retiredKeys) {
      if (_prefs.containsKey(key)) _prefs.remove(key);
    }
  }

  // Keys
  static const _keyWrapText = 'wrapText';
  static const _keyAutoScroll = 'autoScroll';
  static const _keySelectedLogLevel = 'selectedLogLevel';
  static const _keySelectedAndroidLogLevel = 'selectedAndroidLogLevel';
  static const _keySelectedIosLogLevel = 'selectedIosLogLevel';
  static const _keyColumnWidths = 'columnWidths';
  static const _keyHiddenColumns = 'hiddenColumns';
  static const _keyRememberHiddenColumns = 'rememberHiddenColumns';
  static const _keyLogLinesLimit = 'logLinesLimit';
  static const _keyThemeMode = 'themeMode';
  static const _keyLastFileDialogDirectory = 'lastFileDialogDirectory';
  static const _keyLogFontSize = 'logFontSize';
  static const _keyRecentLogFiles = 'recentLogFiles';
  static const _keyTipsEnabled = 'tipsEnabled';
  static const _keyTipRotationIndex = 'tipRotationIndex';
  static const _keySkipIosCaptureNotice = 'skipIosCaptureNotice';
  static const _keySkipIosSupportPrompt = 'skipIosSupportPrompt';
  static const _keyCaptureDirectory = 'captureDirectory';
  static const _keyCaptureAskEveryTime = 'captureAskEveryTime';
  static const _keyAndroidSdkPath = 'androidSdkPath';
  static const _keyAppsViewMode = 'appsViewMode';
  static const _keyAppsIconSize = 'appsIconSize';
  static const _keyWorkspaceLayout = 'workspaceLayout';
  static const _keySavedWorkspaceLayout = 'savedWorkspaceLayout';

  /// Maximum number of recently opened log files retained for quick re-open.
  static const _maxRecentLogFiles = 10;

  /// Default value for [logLinesLimit] when no preference has been saved.
  static const defaultLogLinesLimit = 100000;

  // --- Home page preferences ---

  static bool get wrapText => _prefs.getBool(_keyWrapText) ?? false;
  static set wrapText(bool v) => _prefs.setBool(_keyWrapText, v);

  static bool get autoScroll => _prefs.getBool(_keyAutoScroll) ?? true;
  static set autoScroll(bool v) => _prefs.setBool(_keyAutoScroll, v);

  static LogLevel get selectedLogLevel => LogLevel.fromStored(
    _prefs.getString(_keySelectedLogLevel) ??
        _prefs.getString(_keySelectedAndroidLogLevel) ??
        _prefs.getString(_keySelectedIosLogLevel) ??
        LogLevel.verbose.code,
  );
  static set selectedLogLevel(LogLevel v) =>
      _prefs.setString(_keySelectedLogLevel, v.code);

  static int get logLinesLimit =>
      _prefs.getInt(_keyLogLinesLimit) ?? defaultLogLinesLimit;
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

  // --- Feature tips (header panel) ---
  /// Whether the header feature-tips panel is shown at all. Turning it off is a
  /// permanent, user-driven choice; re-enable from Settings. Listenable so the
  /// Settings toggle and the header panel stay in sync.
  static final ValueNotifier<bool> tipsEnabledListenable = ValueNotifier(true);

  static bool get tipsEnabled => _prefs.getBool(_keyTipsEnabled) ?? true;
  static set tipsEnabled(bool v) {
    tipsEnabledListenable.value = v;
    _prefs.setBool(_keyTipsEnabled, v);
  }

  /// Monotonic counter used to rotate which tip is shown. Advanced once per app
  /// launch so a different tip surfaces each time the app is opened.
  static int get tipRotationIndex => _prefs.getInt(_keyTipRotationIndex) ?? 0;
  static set tipRotationIndex(int v) => _prefs.setInt(_keyTipRotationIndex, v);

  // --- iPhone mirror ---
  /// Whether the user asked not to see, before each iPhone mirror on macOS,
  /// why it needs camera access.
  static bool get skipIosCaptureNotice =>
      _prefs.getBool(_keySkipIosCaptureNotice) ?? false;
  static set skipIosCaptureNotice(bool v) =>
      _prefs.setBool(_keySkipIosCaptureNotice, v);

  // --- iOS on Windows ---
  /// Whether the user asked not to be prompted to install Apple Devices when
  /// an iPhone Eagly can't reach is plugged in. The home screen still says so.
  static bool get skipIosSupportPrompt =>
      _prefs.getBool(_keySkipIosSupportPrompt) ?? false;
  static set skipIosSupportPrompt(bool v) =>
      _prefs.setBool(_keySkipIosSupportPrompt, v);

  // --- Recent log files (most-recent first, capped, for one-click re-open) ---
  /// Listenable so the home screen rebuilds when the list changes.
  static final ValueNotifier<List<String>> recentLogFilesListenable =
      ValueNotifier(const []);

  static List<String> get recentLogFiles =>
      _prefs.getJson<List<String>>(
        _keyRecentLogFiles,
        (json) => (json as List<dynamic>).map((e) => e as String).toList(),
      ) ??
      const [];

  /// Records [path] as the most-recently opened log file, de-duplicating and
  /// capping the list at [_maxRecentLogFiles].
  static Future<void> addRecentLogFile(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return Future<void>.value();

    final next = [normalized, ...recentLogFiles.where((p) => p != normalized)];
    if (next.length > _maxRecentLogFiles) {
      next.removeRange(_maxRecentLogFiles, next.length);
    }
    return _setRecentLogFiles(next);
  }

  static Future<void> removeRecentLogFile(String path) {
    final next = recentLogFiles.where((p) => p != path).toList();
    if (next.length == recentLogFiles.length) return Future<void>.value();
    return _setRecentLogFiles(next);
  }

  static Future<void> _setRecentLogFiles(List<String> value) {
    recentLogFilesListenable.value = List.unmodifiable(value);
    return _prefs.setJson(_keyRecentLogFiles, value);
  }

  // --- Log font size preference (affects the log viewer text size) ---
  static final ValueNotifier<double> logFontSizeListenable = ValueNotifier(
    12.0,
  );

  static double get logFontSize => _prefs.getDouble(_keyLogFontSize) ?? 12.0;
  static set logFontSize(double v) {
    final clamped = (v).clamp(8.0, 24.0);
    final current = logFontSize;
    if ((current - clamped).abs() < 0.0001) return;
    logFontSizeListenable.value = clamped;
    _prefs.setDouble(_keyLogFontSize, clamped);
  }

  // --- Zoom level (scales the entire app: fonts, paddings, dimensions) ---
  static const _keyZoomLevel = 'zoomLevel';
  static const _defaultZoomLevel = 1.0;
  static const _zoomMin = 0.7;
  static const _zoomMax = 1.8;

  static final ValueNotifier<double> zoomLevelListenable = ValueNotifier(
    _defaultZoomLevel,
  );

  static double get zoomLevel =>
      _prefs.getDouble(_keyZoomLevel) ?? _defaultZoomLevel;
  static set zoomLevel(double v) {
    final clamped = v.clamp(_zoomMin, _zoomMax);
    final current = zoomLevel;
    if ((current - clamped).abs() < 0.0001) return;
    zoomLevelListenable.value = clamped;
    _prefs.setDouble(_keyZoomLevel, clamped);
  }

  static LogTabSettings get defaultTabSettings => LogTabSettings(
    wrapText: wrapText,
    autoScroll: autoScroll,
    selectedLogLevel: selectedLogLevel,
    logLinesLimit: logLinesLimit,
    hiddenColumns: hiddenColumns,
    columnWidths: columnWidths,
  );

  // --- Screen capture (screenshots / recordings) ---
  /// Folder screenshots and recordings are written to. `null` means "use the
  /// platform default" — resolved by `CaptureStorage.resolveDirectory()`, which
  /// is also what the Settings screen displays.
  static String? get captureDirectory {
    final stored = _prefs.getString(_keyCaptureDirectory);
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  static Future<bool> setCaptureDirectory(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _prefs.remove(_keyCaptureDirectory);
    }
    return _prefs.setString(_keyCaptureDirectory, value.trim());
  }

  /// When true a save dialog is shown for every capture instead of writing
  /// straight into [captureDirectory].
  static bool get captureAskEveryTime =>
      _prefs.getBool(_keyCaptureAskEveryTime) ?? false;
  static set captureAskEveryTime(bool v) =>
      _prefs.setBool(_keyCaptureAskEveryTime, v);

  // --- Android SDK (emulator manager) ---
  /// Android SDK root the emulator manager should use. `null` means "work it
  /// out" — `AndroidSdkPath.resolveSdkRoot()` then falls back to the env vars
  /// and the platform default. Unlike `adb`, the emulator is not bundled.
  static String? get androidSdkPath {
    final stored = _prefs.getString(_keyAndroidSdkPath);
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  static Future<bool> setAndroidSdkPath(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _prefs.remove(_keyAndroidSdkPath);
    }
    return _prefs.setString(_keyAndroidSdkPath, value.trim());
  }

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

  /// When true, showing or hiding a column in a log tab also saves that set as
  /// [hiddenColumns], so new tabs (and later sessions) open with it. Opting out
  /// leaves the stored set as it was; Settings can reset it.
  static bool get rememberHiddenColumns =>
      _prefs.getBool(_keyRememberHiddenColumns) ?? true;
  static set rememberHiddenColumns(bool v) =>
      _prefs.setBool(_keyRememberHiddenColumns, v);

  static ThemeMode? _themeModeFromName(String? value) {
    return switch (value) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  // --- Apps pane layout (shared by every device's Apps pane) ---

  static AppsViewMode get appsViewMode =>
      AppsViewMode.fromStored(_prefs.getString(_keyAppsViewMode));
  static set appsViewMode(AppsViewMode v) =>
      _prefs.setString(_keyAppsViewMode, v.name);

  static AppIconSize get appsIconSize =>
      AppIconSize.fromStored(_prefs.getString(_keyAppsIconSize));
  static set appsIconSize(AppIconSize v) =>
      _prefs.setString(_keyAppsIconSize, v.name);

  // --- Device workspace layout (shared by every device's workspace) ---

  /// Where each feature pane was last placed, as the JSON
  /// `WorkspaceLayoutMemory.encode` writes; null when nothing is remembered
  /// or the stored value is not JSON. Interpreting it is the layout's job.
  static Map<String, Object?>? get workspaceLayout {
    try {
      return _prefs.getJson<Map<String, Object?>?>(
        _keyWorkspaceLayout,
        (json) => json is Map<String, Object?> ? json : null,
      );
    } on FormatException {
      return null;
    }
  }

  static set workspaceLayout(Map<String, Object?>? v) {
    if (v == null) {
      _prefs.remove(_keyWorkspaceLayout);
    } else {
      _prefs.setJson(_keyWorkspaceLayout, v);
    }
  }

  /// The layout saved for every device to open with, as
  /// `WorkspaceLayoutMemory.encode` writes it; null when none is saved or the
  /// stored value is not JSON.
  static Map<String, Object?>? get savedWorkspaceLayout {
    try {
      return _prefs.getJson<Map<String, Object?>?>(
        _keySavedWorkspaceLayout,
        (json) => json is Map<String, Object?> ? json : null,
      );
    } on FormatException {
      return null;
    }
  }

  static set savedWorkspaceLayout(Map<String, Object?>? v) {
    if (v == null) {
      _prefs.remove(_keySavedWorkspaceLayout);
    } else {
      _prefs.setJson(_keySavedWorkspaceLayout, v);
    }
  }
}
