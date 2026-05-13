import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/log_entry.dart';
import '../../data/log_level.dart';
import '../../utils/log_buffer.dart'; // For LogFilter typedef

enum _LogFilterField { message, packageName, pidTid, tag }

class LogFilterController extends ChangeNotifier {
  static const int _maxRecentFilterValues = 8;

  LogFilterController();

  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController packageFilterController = TextEditingController();
  final FocusNode packageFilterFocusNode = FocusNode();
  final TextEditingController pidTidFilterController = TextEditingController();
  final FocusNode pidTidFilterFocusNode = FocusNode();
  final TextEditingController tagFilterController = TextEditingController();
  final FocusNode tagFilterFocusNode = FocusNode();

  var searchQuery = '';
  var _appliedSearchQuery = '';
  var packageFilterQuery = '';
  var _appliedPackageFilterQuery = '';
  var pidTidFilterQuery = '';
  var _appliedPidTidFilterQuery = '';
  var tagFilterQuery = '';
  var _appliedTagFilterQuery = '';

  final List<String> _recentMessageFilters = [];
  final List<String> _recentPackageFilters = [];
  final List<String> _recentPidTidFilters = [];
  final List<String> _recentTagFilters = [];

  Timer? _debounceTimer;
  Timer? _filterSaveDebounceTimer;

  LogLevel _selectedLogLevel = LogLevel.verbose;

  String get appliedSearchQuery => _appliedSearchQuery;
  String get appliedPackageFilterQuery => _appliedPackageFilterQuery;
  String get appliedPidTidFilterQuery => _appliedPidTidFilterQuery;
  String get appliedTagFilterQuery => _appliedTagFilterQuery;
  LogLevel get selectedLogLevel => _selectedLogLevel;

  List<String> get recentMessageFilters =>
      List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters =>
      List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters =>
      List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);

  /// Called by the parent controller after settings are loaded.
  void initFromSettings({
    required String searchQuery,
    required String packageFilterQuery,
    required String pidTidFilterQuery,
    required String tagFilterQuery,
    required LogLevel selectedLogLevel,
  }) {
    this.searchQuery = searchQuery;
    this.packageFilterQuery = packageFilterQuery;
    this.pidTidFilterQuery = pidTidFilterQuery;
    this.tagFilterQuery = tagFilterQuery;
    _selectedLogLevel = selectedLogLevel;
    filterController.text = searchQuery;
    packageFilterController.text = packageFilterQuery;
    pidTidFilterController.text = pidTidFilterQuery;
    tagFilterController.text = tagFilterQuery;
  }

  void setSelectedLogLevel(LogLevel level) {
    _selectedLogLevel = level;
    notifyListeners();
  }

  void focusFilterInputs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      filterFocusNode.requestFocus();
      filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filterController.text.length,
      );
    });
  }

  void clearFilter() {
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    filterController.clear();
    packageFilterController.clear();
    pidTidFilterController.clear();
    tagFilterController.clear();
    searchQuery = '';
    _appliedSearchQuery = '';
    packageFilterQuery = '';
    _appliedPackageFilterQuery = '';
    pidTidFilterQuery = '';
    _appliedPidTidFilterQuery = '';
    tagFilterQuery = '';
    _appliedTagFilterQuery = '';
    focusFilterInputs();
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
    _applyTextFilters();
  }

  // --- Filter matching logic ---

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

  bool matchesLogFilters(LogEntry log) {
    final selectedLevel = _selectedLogLevel;
    if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
      return false;
    }

    final packageQuery = _appliedPackageFilterQuery.toLowerCase();
    if (packageQuery.isNotEmpty &&
        !_packageFilterValue(log).toLowerCase().contains(packageQuery)) {
      return false;
    }

    final pidTidQuery = _appliedPidTidFilterQuery.toLowerCase();
    if (pidTidQuery.isNotEmpty && !_matchesPidTidFilter(log, pidTidQuery)) {
      return false;
    }

    final tagQuery = _appliedTagFilterQuery.toLowerCase();
    if (tagQuery.isNotEmpty && !log.tag.toLowerCase().contains(tagQuery)) {
      return false;
    }

    final messageQuery = _appliedSearchQuery.toLowerCase();
    if (messageQuery.isNotEmpty &&
        !log.message.toLowerCase().contains(messageQuery)) {
      return false;
    }

    return true;
  }

  bool get hasActiveRetentionFilter {
    return _selectedLogLevel.hierarchy < LogLevel.verbose.hierarchy ||
        _appliedSearchQuery.isNotEmpty ||
        _appliedPackageFilterQuery.isNotEmpty ||
        _appliedPidTidFilterQuery.isNotEmpty ||
        _appliedTagFilterQuery.isNotEmpty;
  }

  LogFilter<LogEntry>? get retentionFilter =>
      hasActiveRetentionFilter ? matchesLogFilters : null;

  // --- Private ---

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

    if (applyImmediately) {
      _applyTextFilters();
      return;
    }

    notifyListeners();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _applyTextFilters();
    });
  }

  void _applyTextFilters() {
    _appliedSearchQuery = searchQuery.trim();
    _appliedPackageFilterQuery = packageFilterQuery.trim();
    _appliedPidTidFilterQuery = pidTidFilterQuery.trim();
    _appliedTagFilterQuery = tagFilterQuery.trim();

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });
    notifyListeners();
  }

  void _rememberRecentFilterValues() {
    _rememberRecentFilterValue(_recentMessageFilters, _appliedSearchQuery);
    _rememberRecentFilterValue(
      _recentPackageFilters,
      _appliedPackageFilterQuery,
    );
    _rememberRecentFilterValue(_recentPidTidFilters, _appliedPidTidFilterQuery);
    _rememberRecentFilterValue(_recentTagFilters, _appliedTagFilterQuery);
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
    super.dispose();
  }
}


