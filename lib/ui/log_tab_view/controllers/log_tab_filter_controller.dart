import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/log_entry.dart';
import '../../../data/log_level.dart';
import '../../../utils/log_buffer.dart';

class LogTabFilterController {
  static const int defaultMaxRecentValues = 8;

  LogTabFilterController({
    required this.onChanged,
    required this.onFiltersApplied,
    required this.onSelectionCleared,
    required this.isDisposed,
    this.maxRecentValues = defaultMaxRecentValues,
  });

  final VoidCallback onChanged;
  final VoidCallback onFiltersApplied;
  final VoidCallback onSelectionCleared;
  final bool Function() isDisposed;
  final int maxRecentValues;

  final TextEditingController messageController = TextEditingController();
  final FocusNode messageFocusNode = FocusNode();
  final TextEditingController packageController = TextEditingController();
  final FocusNode packageFocusNode = FocusNode();
  final TextEditingController pidTidController = TextEditingController();
  final FocusNode pidTidFocusNode = FocusNode();
  final TextEditingController tagController = TextEditingController();
  final FocusNode tagFocusNode = FocusNode();

  Timer? _debounceTimer;
  Timer? _saveDebounceTimer;

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

  String get appliedSearchQuery => _appliedSearchQuery;
  String get appliedPackageFilterQuery => _appliedPackageFilterQuery;
  String get appliedPidTidFilterQuery => _appliedPidTidFilterQuery;
  String get appliedTagFilterQuery => _appliedTagFilterQuery;

  List<String> get recentMessageFilters =>
      List.unmodifiable(_recentMessageFilters);
  List<String> get recentPackageFilters =>
      List.unmodifiable(_recentPackageFilters);
  List<String> get recentPidTidFilters =>
      List.unmodifiable(_recentPidTidFilters);
  List<String> get recentTagFilters => List.unmodifiable(_recentTagFilters);

  void focusPrimaryField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDisposed()) return;
      messageFocusNode.requestFocus();
      messageController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: messageController.text.length,
      );
    });
  }

  void clear() {
    _debounceTimer?.cancel();
    _saveDebounceTimer?.cancel();
    onSelectionCleared();
    messageController.clear();
    packageController.clear();
    pidTidController.clear();
    tagController.clear();
    searchQuery = '';
    _appliedSearchQuery = '';
    packageFilterQuery = '';
    _appliedPackageFilterQuery = '';
    pidTidFilterQuery = '';
    _appliedPidTidFilterQuery = '';
    tagFilterQuery = '';
    _appliedTagFilterQuery = '';
    onFiltersApplied();
    focusPrimaryField();
    onChanged();
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

  bool matchesLog(LogEntry log, {required LogLevel selectedLevel}) {
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

  bool hasActiveRetentionFilter(LogLevel selectedLevel) {
    return selectedLevel.hierarchy < LogLevel.verbose.hierarchy ||
        _appliedSearchQuery.isNotEmpty ||
        _appliedPackageFilterQuery.isNotEmpty ||
        _appliedPidTidFilterQuery.isNotEmpty ||
        _appliedTagFilterQuery.isNotEmpty;
  }

  LogFilter<LogEntry>? retentionFilter(LogLevel selectedLevel) {
    if (!hasActiveRetentionFilter(selectedLevel)) {
      return null;
    }
    return (log) => matchesLog(log, selectedLevel: selectedLevel);
  }

  void dispose() {
    _debounceTimer?.cancel();
    _saveDebounceTimer?.cancel();
    messageController.dispose();
    messageFocusNode.dispose();
    packageController.dispose();
    packageFocusNode.dispose();
    pidTidController.dispose();
    pidTidFocusNode.dispose();
    tagController.dispose();
    tagFocusNode.dispose();
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
        if (messageController.text != value) {
          messageController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.packageName:
        packageFilterQuery = value;
        if (packageController.text != value) {
          packageController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.pidTid:
        pidTidFilterQuery = value;
        if (pidTidController.text != value) {
          pidTidController.value = TextEditingValue(
            text: value,
            selection: selection,
          );
        }
        break;
      case _LogFilterField.tag:
        tagFilterQuery = value;
        if (tagController.text != value) {
          tagController.value = TextEditingValue(
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

    onChanged();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (isDisposed()) return;
      _applyTextFilters();
    });
  }

  void _applyTextFilters() {
    _appliedSearchQuery = searchQuery.trim();
    _appliedPackageFilterQuery = packageFilterQuery.trim();
    _appliedPidTidFilterQuery = pidTidFilterQuery.trim();
    _appliedTagFilterQuery = tagFilterQuery.trim();
    onSelectionCleared();

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _rememberRecentFilterValues();
    });
    onFiltersApplied();
    onChanged();
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

    if (recentValues.length > maxRecentValues) {
      recentValues.removeRange(maxRecentValues, recentValues.length);
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
}

enum _LogFilterField { message, packageName, pidTid, tag }
