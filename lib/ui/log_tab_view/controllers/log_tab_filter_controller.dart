import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/log_entry.dart';
import '../../../data/log_level.dart';
import '../../../data/log_view_mode.dart';
import '../../../utils/log_buffer.dart';
import '../components/inline_filter_bar.dart';

class LogTabFilterController extends ChangeNotifier {
  static const int _maxRecentFilterValues = 8;

  LogTabFilterController({
    required LogLevel initialSelectedLogLevel,
    required LogFilterViewMode initialFilterViewMode,
    required bool Function() isIosContextProvider,
    required VoidCallback onAppliedFiltersChanged,
  }) : _selectedLogLevel = initialSelectedLogLevel,
       _filterViewMode = initialFilterViewMode,
       _isIosContextProvider = isIosContextProvider,
       _onAppliedFiltersChanged = onAppliedFiltersChanged {
    filterController.text = searchQuery;
    packageFilterController.text = packageFilterQuery;
    pidTidFilterController.text = pidTidFilterQuery;
    tagFilterController.text = tagFilterQuery;
    inlineFilterController.text = _composeInlineFilterText();
  }

  final bool Function() _isIosContextProvider;
  final VoidCallback _onAppliedFiltersChanged;

  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController packageFilterController = TextEditingController();
  final FocusNode packageFilterFocusNode = FocusNode();
  final TextEditingController pidTidFilterController = TextEditingController();
  final FocusNode pidTidFilterFocusNode = FocusNode();
  final TextEditingController tagFilterController = TextEditingController();
  final FocusNode tagFilterFocusNode = FocusNode();
  final InlineFilterTextController inlineFilterController =
      InlineFilterTextController();
  final FocusNode inlineFilterFocusNode = FocusNode();

  Timer? _debounceTimer;
  Timer? _filterSaveDebounceTimer;

  LogLevel _selectedLogLevel;
  LogFilterViewMode _filterViewMode;
  var searchQuery = '';
  var packageFilterQuery = '';
  var pidTidFilterQuery = '';
  var tagFilterQuery = '';
  var _inlineFilterText = '';

  final List<String> _recentMessageFilters = [];
  final List<String> _recentPackageFilters = [];
  final List<String> _recentPidTidFilters = [];
  final List<String> _recentTagFilters = [];
  List<String> _knownInlinePackageFilters = const [];
  int _knownInlinePackageFingerprintLength = -1;
  int? _knownInlinePackageFingerprintFirstId;
  int? _knownInlinePackageFingerprintLastId;

  List<String> _appliedMessageTerms = const [];
  List<String> _appliedRawTerms = const [];
  List<String> _appliedPackageTerms = const [];
  List<String> _appliedPidTidTerms = const [];
  List<String> _appliedTagTerms = const [];

  LogLevel get selectedLogLevel => _selectedLogLevel;
  LogFilterViewMode get filterViewMode => _filterViewMode;
  List<String> get recentMessageFilters =>
      List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters =>
      List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters =>
      List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);

  String get appliedFilterSignature => [
    selectedLogLevel.code,
    'm:${_appliedMessageTerms.join('\u0001')}',
    'r:${_appliedRawTerms.join('\u0001')}',
    'p:${_appliedPackageTerms.join('\u0001')}',
    'pt:${_appliedPidTidTerms.join('\u0001')}',
    't:${_appliedTagTerms.join('\u0001')}',
  ].join('\u0000');

  LogFilter<LogEntry>? get retentionFilter =>
      _hasActiveRetentionFilter ? matchesLogFilters : null;

  List<String> knownInlinePackageFilters(List<LogEntry> storedLogs) {
    final firstId = storedLogs.isEmpty ? null : storedLogs.first.id;
    final lastId = storedLogs.isEmpty ? null : storedLogs.last.id;
    if (_knownInlinePackageFingerprintLength == storedLogs.length &&
        _knownInlinePackageFingerprintFirstId == firstId &&
        _knownInlinePackageFingerprintLastId == lastId) {
      return List.unmodifiable(_knownInlinePackageFilters);
    }

    final counts = <String, int>{};
    for (final log in storedLogs) {
      final value = _packageFilterValue(log).trim();
      if (value.isEmpty) continue;
      counts.update(value, (count) => count + 1, ifAbsent: () => 1);
    }

    final sortedValues = counts.keys.toList(growable: false)
      ..sort((left, right) {
        final countComparison = counts[right]!.compareTo(counts[left]!);
        if (countComparison != 0) return countComparison;
        return left.toLowerCase().compareTo(right.toLowerCase());
      });

    _knownInlinePackageFilters = sortedValues;
    _knownInlinePackageFingerprintLength = storedLogs.length;
    _knownInlinePackageFingerprintFirstId = firstId;
    _knownInlinePackageFingerprintLastId = lastId;
    return List.unmodifiable(_knownInlinePackageFilters);
  }

  void clearFilter() {
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: _isIosContextProvider(),
    );
    filterController.clear();
    packageFilterController.clear();
    pidTidFilterController.clear();
    tagFilterController.clear();
    inlineFilterController.clear();
    _inlineFilterText = '';
    searchQuery = '';
    packageFilterQuery = '';
    pidTidFilterQuery = '';
    tagFilterQuery = '';
    _selectedLogLevel = defaultLevel;
    _appliedMessageTerms = const [];
    _appliedRawTerms = const [];
    _appliedPackageTerms = const [];
    _appliedPidTidTerms = const [];
    _appliedTagTerms = const [];
    _onAppliedFiltersChanged();
    notifyListeners();
  }

  void onInlineFilterChanged(String value) {
    _inlineFilterText = value;
    if (inlineFilterController.text != value) {
      inlineFilterController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    notifyListeners();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _applyInlineFilters);
  }

  void setInlineFilterText(
    String value, {
    TextSelection? selection,
    bool applyImmediately = false,
  }) {
    _inlineFilterText = value;
    inlineFilterController.value = TextEditingValue(
      text: value,
      selection: selection ?? TextSelection.collapsed(offset: value.length),
    );
    if (applyImmediately) {
      _debounceTimer?.cancel();
      _applyInlineFilters();
      return;
    }
    notifyListeners();
  }

  void onSearchChanged(String value) {
    _setFilterField(_LogFilterField.message, value);
  }

  void onPackageFilterChanged(String value) {
    _setFilterField(_LogFilterField.packageName, value);
  }

  void onPidTidFilterChanged(String value) {
    _setFilterField(_LogFilterField.pidTid, value);
  }

  void onTagFilterChanged(String value) {
    _setFilterField(_LogFilterField.tag, value);
  }

  void selectMessageFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.message, value, applyImmediately: true);
  }

  void selectPackageFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.packageName, value, applyImmediately: true);
  }

  void selectPidTidFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.pidTid, value, applyImmediately: true);
  }

  void selectTagFilterSuggestion(String value) {
    _setFilterField(_LogFilterField.tag, value, applyImmediately: true);
  }

  void applyFiltersNow() {
    _debounceTimer?.cancel();
    switch (filterViewMode) {
      case LogFilterViewMode.classic:
        _applyTextFilters();
      case LogFilterViewMode.inline:
        _applyInlineFilters();
    }
  }

  void setSelectedLogLevel(LogLevel level) {
    if (_selectedLogLevel == level) return;
    _selectedLogLevel = level;
    _syncInlineFilterText();
    _onAppliedFiltersChanged();
    notifyListeners();
  }

  void setFilterViewMode(LogFilterViewMode mode) {
    if (_filterViewMode == mode) return;
    _filterViewMode = mode;
    notifyListeners();
  }

  bool matchesLogFilters(LogEntry log) {
    final selectedLevel = selectedLogLevel;
    if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
      return false;
    }

    if (!_matchesAllTerms(
      _packageFilterValue(log),
      _appliedPackageTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    if (!_matchesAllTerms(
      log.lowercaseSearchable,
      _appliedRawTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    if (_appliedPidTidTerms.any((query) => !_matchesPidTidFilter(log, query))) {
      return false;
    }

    if (!_matchesAllTerms(log.tag, _appliedTagTerms, caseSensitive: false)) {
      return false;
    }

    if (!_matchesAllTerms(
      log.message,
      _appliedMessageTerms,
      caseSensitive: false,
    )) {
      return false;
    }

    return true;
  }

  void _setFilterField(
    _LogFilterField field,
    String value, {
    bool applyImmediately = false,
  }) {
    final selection = TextSelection.collapsed(offset: value.length);

    switch (field) {
      case _LogFilterField.message:
        searchQuery = value;
        if (filterController.text != value) {
          filterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.packageName:
        packageFilterQuery = value;
        if (packageFilterController.text != value) {
          packageFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.pidTid:
        pidTidFilterQuery = value;
        if (pidTidFilterController.text != value) {
          pidTidFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.tag:
        tagFilterQuery = value;
        if (tagFilterController.text != value) {
          tagFilterController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
    }

    _syncInlineFilterText();

    if (applyImmediately) {
      _applyTextFilters();
      return;
    }

    notifyListeners();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _applyTextFilters);
  }

  void _applyTextFilters() {
    _applyParsedFilters(_parsedFiltersFromClassicInputs());
  }

  void _applyInlineFilters() {
    final parsedFilters = _parseInlineFilters(
      _inlineFilterText,
      fallbackLevel: LogLevel.defaultSelectionForPlatform(
        isIos: _isIosContextProvider(),
      ),
    );
    _applyInlineDraftFilters(parsedFilters);
    _applyParsedFilters(parsedFilters);
  }

  void _applyParsedFilters(_ParsedLogFilters parsedFilters) {
    _appliedMessageTerms = parsedFilters.messageTerms;
    _appliedRawTerms = parsedFilters.rawTerms;
    _appliedPackageTerms = parsedFilters.packageTerms;
    _appliedPidTidTerms = parsedFilters.pidTidTerms;
    _appliedTagTerms = parsedFilters.tagTerms;
    _selectedLogLevel = parsedFilters.level;

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });

    _onAppliedFiltersChanged();
    notifyListeners();
  }

  void _rememberRecentFilterValues() {
    for (final value in _appliedMessageTerms) {
      _rememberRecentFilterValue(_recentMessageFilters, value);
    }
    for (final value in _appliedPackageTerms) {
      _rememberRecentFilterValue(_recentPackageFilters, value);
    }
    for (final value in _appliedPidTidTerms) {
      _rememberRecentFilterValue(_recentPidTidFilters, value);
    }
    for (final value in _appliedTagTerms) {
      _rememberRecentFilterValue(_recentTagFilters, value);
    }
  }

  void _rememberRecentFilterValue(List<String> recentValues, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;

    recentValues.removeWhere(
      (existing) => existing.toLowerCase() == normalized.toLowerCase(),
    );
    recentValues.insert(0, normalized);

    if (recentValues.length > _maxRecentFilterValues) {
      recentValues.removeRange(_maxRecentFilterValues, recentValues.length);
    }
  }

  _ParsedLogFilters _parsedFiltersFromClassicInputs() {
    return _ParsedLogFilters(
      messageText: searchQuery.trim(),
      packageText: packageFilterQuery.trim(),
      pidTidText: pidTidFilterQuery.trim(),
      tagText: tagFilterQuery.trim(),
      messageTerms: _singleTerm(searchQuery),
      rawTerms: const [],
      packageTerms: _singleTerm(packageFilterQuery),
      pidTidTerms: _singleTerm(pidTidFilterQuery),
      tagTerms: _singleTerm(tagFilterQuery),
      level: selectedLogLevel,
    );
  }

  void _applyInlineDraftFilters(_ParsedLogFilters parsedFilters) {
    searchQuery = parsedFilters.messageText;
    packageFilterQuery = parsedFilters.packageText;
    pidTidFilterQuery = parsedFilters.pidTidText;
    tagFilterQuery = parsedFilters.tagText;

    _setControllerTextIfNeeded(filterController, parsedFilters.messageText);
    _setControllerTextIfNeeded(
      packageFilterController,
      parsedFilters.packageText,
    );
    _setControllerTextIfNeeded(pidTidFilterController, parsedFilters.pidTidText);
    _setControllerTextIfNeeded(tagFilterController, parsedFilters.tagText);
  }

  void _setControllerTextIfNeeded(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  List<String> _singleTerm(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? const [] : [normalized];
  }

  void _syncInlineFilterText() {
    final nextValue = _composeInlineFilterText();
    _inlineFilterText = nextValue;
    if (inlineFilterController.text == nextValue) return;
    inlineFilterController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  String _composeInlineFilterText() {
    final tokens = <String>[];
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: _isIosContextProvider(),
    );
    if (selectedLogLevel != defaultLevel) {
      tokens.add(_serializeInlineToken('level', selectedLogLevel.code));
    }
    if (packageFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('package', packageFilterQuery.trim()));
    }
    if (pidTidFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('pid', pidTidFilterQuery.trim()));
    }
    if (tagFilterQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('tag', tagFilterQuery.trim()));
    }
    if (searchQuery.trim().isNotEmpty) {
      tokens.add(_serializeInlineToken('message', searchQuery.trim()));
    }
    return tokens.join(' ');
  }

  String _serializeInlineToken(String key, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';

    final needsQuotes =
        normalized.contains(RegExp(r'\s')) || normalized.contains('"');
    if (!needsQuotes) {
      return '$key:$normalized';
    }

    final escaped = normalized.replaceAll('"', r'\"');
    return '$key:"$escaped"';
  }

  _ParsedLogFilters _parseInlineFilters(
    String rawText, {
    required LogLevel fallbackLevel,
  }) {
    final messageTerms = <String>[];
    final rawTerms = <String>[];
    final packageTerms = <String>[];
    final pidTidTerms = <String>[];
    final tagTerms = <String>[];
    var parsedLevel = fallbackLevel;

    for (final token in _tokenizeInlineFilterText(rawText)) {
      final trimmedToken = token.trim();
      if (trimmedToken.isEmpty) continue;

      final colonIndex = trimmedToken.indexOf(':');
      if (colonIndex <= 0) {
        final messageValue = _normalizeInlineFilterValue(trimmedToken);
        if (messageValue.isNotEmpty) {
          rawTerms.add(messageValue);
        }
        continue;
      }

      final rawKey = trimmedToken.substring(0, colonIndex);
      final rawValue = trimmedToken.substring(colonIndex + 1);
      final key = _canonicalInlineFilterKey(rawKey);
      final value = _normalizeInlineFilterValue(rawValue);
      if (key == null || value.isEmpty) {
        final fallbackValue = _normalizeInlineFilterValue(trimmedToken);
        if (fallbackValue.isNotEmpty) {
          rawTerms.add(fallbackValue);
        }
        continue;
      }

      switch (key) {
        case _InlineFilterKey.message:
          messageTerms.add(value);
        case _InlineFilterKey.packageName:
          packageTerms.add(value);
        case _InlineFilterKey.pidTid:
          pidTidTerms.add(value.toLowerCase());
        case _InlineFilterKey.tag:
          tagTerms.add(value);
        case _InlineFilterKey.level:
          parsedLevel = LogLevel.fromStored(
            value,
          ).normalizeSelectionForPlatform(isIos: _isIosContextProvider());
      }
    }

    final messageFieldTerms = <String>[...rawTerms, ...messageTerms];
    return _ParsedLogFilters(
      messageText: messageFieldTerms.join(' '),
      packageText: packageTerms.join(' '),
      pidTidText: pidTidTerms.join(' '),
      tagText: tagTerms.join(' '),
      messageTerms: List.unmodifiable(messageTerms),
      rawTerms: List.unmodifiable(rawTerms),
      packageTerms: List.unmodifiable(packageTerms),
      pidTidTerms: List.unmodifiable(pidTidTerms),
      tagTerms: List.unmodifiable(tagTerms),
      level: parsedLevel,
    );
  }

  List<String> _tokenizeInlineFilterText(String rawText) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (final rune in rawText.runes) {
      final char = String.fromCharCode(rune);
      if (char == '"') {
        inQuotes = !inQuotes;
        buffer.write(char);
        continue;
      }
      if (!inQuotes && RegExp(r'\s').hasMatch(char)) {
        final token = buffer.toString().trim();
        if (token.isNotEmpty) {
          tokens.add(token);
        }
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }

    final finalToken = buffer.toString().trim();
    if (finalToken.isNotEmpty) {
      tokens.add(finalToken);
    }
    return tokens;
  }

  _InlineFilterKey? _canonicalInlineFilterKey(String rawKey) {
    return switch (rawKey.trim().toLowerCase()) {
      'message' || 'msg' || 'text' => _InlineFilterKey.message,
      'package' || 'pkg' || 'app' || 'process' => _InlineFilterKey.packageName,
      'pid' || 'tid' || 'thread' || 'pidtid' => _InlineFilterKey.pidTid,
      'tag' => _InlineFilterKey.tag,
      'level' || 'lvl' || 'priority' => _InlineFilterKey.level,
      _ => null,
    };
  }

  String _normalizeInlineFilterValue(String rawValue) {
    var normalized = rawValue.trim();
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized.replaceAll(r'\"', '"').trim();
  }

  bool _matchesAllTerms(
    String candidate,
    List<String> terms, {
    required bool caseSensitive,
  }) {
    if (terms.isEmpty) return true;
    final normalizedCandidate = caseSensitive
        ? candidate
        : candidate.toLowerCase();
    return terms.every((term) {
      final normalizedTerm = caseSensitive ? term : term.toLowerCase();
      return normalizedCandidate.contains(normalizedTerm);
    });
  }

  String _packageFilterValue(LogEntry log) {
    final packageName = log.packageName?.trim();
    if (packageName != null && packageName.isNotEmpty) return packageName;

    final processName = log.processName?.trim();
    if (processName != null && processName.isNotEmpty) return processName;

    return '';
  }

  bool _matchesPidTidFilter(LogEntry log, String query) {
    final pid = log.pid.toLowerCase();
    final tid = log.tid.toLowerCase();
    return pid.contains(query) ||
        tid.contains(query) ||
        '$pid/$tid'.contains(query) ||
        '$pid:$tid'.contains(query);
  }

  bool get _hasActiveRetentionFilter {
    final defaultLevel = LogLevel.defaultSelectionForPlatform(
      isIos: _isIosContextProvider(),
    );
    return selectedLogLevel.hierarchy < defaultLevel.hierarchy ||
        _appliedMessageTerms.isNotEmpty ||
        _appliedRawTerms.isNotEmpty ||
        _appliedPackageTerms.isNotEmpty ||
        _appliedPidTidTerms.isNotEmpty ||
        _appliedTagTerms.isNotEmpty;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    filterController.dispose();
    filterFocusNode.dispose();
    packageFilterController.dispose();
    packageFilterFocusNode.dispose();
    pidTidFilterController.dispose();
    pidTidFilterFocusNode.dispose();
    tagFilterController.dispose();
    tagFilterFocusNode.dispose();
    inlineFilterController.dispose();
    inlineFilterFocusNode.dispose();
    super.dispose();
  }
}

enum _LogFilterField { message, packageName, pidTid, tag }

enum _InlineFilterKey { message, packageName, pidTid, tag, level }

class _ParsedLogFilters {
  const _ParsedLogFilters({
    required this.messageText,
    required this.packageText,
    required this.pidTidText,
    required this.tagText,
    required this.messageTerms,
    required this.rawTerms,
    required this.packageTerms,
    required this.pidTidTerms,
    required this.tagTerms,
    required this.level,
  });

  final String messageText;
  final String packageText;
  final String pidTidText;
  final String tagText;
  final List<String> messageTerms;
  final List<String> rawTerms;
  final List<String> packageTerms;
  final List<String> pidTidTerms;
  final List<String> tagTerms;
  final LogLevel level;
}

