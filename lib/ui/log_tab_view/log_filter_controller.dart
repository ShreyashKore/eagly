import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/log_entry.dart';
import '../../data/log_level.dart';

/// Manages the filter fields (message, package, pid/tid, tag) and their
/// applied state, debouncing, and recent-values history.
class LogFilterController extends ChangeNotifier {
  static const int _maxRecentFilterValues = 8;

  LogFilterController({required LogLevel Function() selectedLogLevelProvider}) {
    _selectedLogLevelProvider = selectedLogLevelProvider;
  }

  late final LogLevel Function() _selectedLogLevelProvider;

  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController packageFilterController = TextEditingController();
  final FocusNode packageFilterFocusNode = FocusNode();
  final TextEditingController pidTidFilterController = TextEditingController();
  final FocusNode pidTidFilterFocusNode = FocusNode();
  final TextEditingController tagFilterController = TextEditingController();
  final FocusNode tagFilterFocusNode = FocusNode();

  Timer? _debounceTimer;
  Timer? _filterSaveDebounceTimer;

  var searchQuery = '';
  var appliedSearchQuery = '';
  var packageFilterQuery = '';
  var appliedPackageFilterQuery = '';
  var pidTidFilterQuery = '';
  var appliedPidTidFilterQuery = '';
  var tagFilterQuery = '';
  var appliedTagFilterQuery = '';

  final List<String> _recentMessageFilters = [];
  final List<String> _recentPackageFilters = [];
  final List<String> _recentPidTidFilters = [];
  final List<String> _recentTagFilters = [];

  bool _disposed = false;

  // Callback invoked when applied filters change so the parent can
  // re-sync the log buffer filter and invalidate caches.
  VoidCallback? onFiltersApplied;

  List<String> get recentMessageFilters => List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters => List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters => List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);

  bool get hasActiveRetentionFilter {
    final selectedLevel = _selectedLogLevelProvider();
    return selectedLevel.hierarchy < LogLevel.verbose.hierarchy ||
        appliedSearchQuery.isNotEmpty ||
        appliedPackageFilterQuery.isNotEmpty ||
        appliedPidTidFilterQuery.isNotEmpty ||
        appliedTagFilterQuery.isNotEmpty;
  }

  bool matchesLogFilters(LogEntry log) {
    final selectedLevel = _selectedLogLevelProvider();
    if (LogLevel.fromStored(log.level).hierarchy > selectedLevel.hierarchy) {
      return false;
    }

    final packageQuery = appliedPackageFilterQuery.toLowerCase();
    if (packageQuery.isNotEmpty &&
        !_packageFilterValue(log).toLowerCase().contains(packageQuery)) {
      return false;
    }

    final pidTidQuery = appliedPidTidFilterQuery.toLowerCase();
    if (pidTidQuery.isNotEmpty && !_matchesPidTidFilter(log, pidTidQuery)) {
      return false;
    }

    final tagQuery = appliedTagFilterQuery.toLowerCase();
    if (tagQuery.isNotEmpty && !log.tag.toLowerCase().contains(tagQuery)) {
      return false;
    }

    final messageQuery = appliedSearchQuery.toLowerCase();
    if (messageQuery.isNotEmpty &&
        !log.message.toLowerCase().contains(messageQuery)) {
      return false;
    }

    return true;
  }

  void initFromSettings({
    required String searchQuery,
    required String packageFilterQuery,
    required String pidTidFilterQuery,
    required String tagFilterQuery,
  }) {
    this.searchQuery = searchQuery;
    this.packageFilterQuery = packageFilterQuery;
    this.pidTidFilterQuery = pidTidFilterQuery;
    this.tagFilterQuery = tagFilterQuery;
    filterController.text = searchQuery;
    packageFilterController.text = packageFilterQuery;
    pidTidFilterController.text = pidTidFilterQuery;
    tagFilterController.text = tagFilterQuery;
  }

  void onSearchChanged(String value) =>
      _setField(_FilterField.message, value);

  void onPackageFilterChanged(String value) =>
      _setField(_FilterField.packageName, value);

  void onPidTidFilterChanged(String value) =>
      _setField(_FilterField.pidTid, value);

  void onTagFilterChanged(String value) =>
      _setField(_FilterField.tag, value);

  void selectMessageFilterSuggestion(String value) =>
      _setField(_FilterField.message, value, applyImmediately: true);

  void selectPackageFilterSuggestion(String value) =>
      _setField(_FilterField.packageName, value, applyImmediately: true);

  void selectPidTidFilterSuggestion(String value) =>
      _setField(_FilterField.pidTid, value, applyImmediately: true);

  void selectTagFilterSuggestion(String value) =>
      _setField(_FilterField.tag, value, applyImmediately: true);

  void applyFiltersNow() {
    _debounceTimer?.cancel();
    _applyTextFilters();
  }

  void clearFilter() {
    _debounceTimer?.cancel();
    _filterSaveDebounceTimer?.cancel();
    filterController.clear();
    packageFilterController.clear();
    pidTidFilterController.clear();
    tagFilterController.clear();
    searchQuery = '';
    appliedSearchQuery = '';
    packageFilterQuery = '';
    appliedPackageFilterQuery = '';
    pidTidFilterQuery = '';
    appliedPidTidFilterQuery = '';
    tagFilterQuery = '';
    appliedTagFilterQuery = '';
    onFiltersApplied?.call();
    _focusFilterInputs();
    notifyListeners();
  }

  void _focusFilterInputs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      filterFocusNode.requestFocus();
      filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filterController.text.length,
      );
    });
  }

  void focusFilterInputs() => _focusFilterInputs();

  void _setField(
    _FilterField field,
    String value, {
    bool applyImmediately = false,
  }) {
    final selection = TextSelection.collapsed(offset: value.length);

    switch (field) {
      case _FilterField.message:
        searchQuery = value;
        if (filterController.text != value) {
          filterController.value = TextEditingValue(text: value, selection: selection);
        }
        break;
      case _FilterField.packageName:
        packageFilterQuery = value;
        if (packageFilterController.text != value) {
          packageFilterController.value = TextEditingValue(text: value, selection: selection);
        }
        break;
      case _FilterField.pidTid:
        pidTidFilterQuery = value;
        if (pidTidFilterController.text != value) {
          pidTidFilterController.value = TextEditingValue(text: value, selection: selection);
        }
        break;
      case _FilterField.tag:
        tagFilterQuery = value;
        if (tagFilterController.text != value) {
          tagFilterController.value = TextEditingValue(text: value, selection: selection);
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
      if (_disposed) return;
      _applyTextFilters();
    });
  }

  void _applyTextFilters() {
    appliedSearchQuery = searchQuery.trim();
    appliedPackageFilterQuery = packageFilterQuery.trim();
    appliedPidTidFilterQuery = pidTidFilterQuery.trim();
    appliedTagFilterQuery = tagFilterQuery.trim();

    _filterSaveDebounceTimer?.cancel();
    _filterSaveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });

    onFiltersApplied?.call();
    notifyListeners();
  }

  void _rememberRecentFilterValues() {
    _rememberRecentFilterValue(_recentMessageFilters, appliedSearchQuery);
    _rememberRecentFilterValue(_recentPackageFilters, appliedPackageFilterQuery);
    _rememberRecentFilterValue(_recentPidTidFilters, appliedPidTidFilterQuery);
    _rememberRecentFilterValue(_recentTagFilters, appliedTagFilterQuery);
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

  @override
  void dispose() {
    _disposed = true;
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

enum _FilterField { message, packageName, pidTid, tag }

