import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/log_column.dart';
import '../../../data/log_entry.dart';
import '../../../utils/text_search_pattern.dart';

class LogTabSearchController {
  LogTabSearchController({
    required this.onChanged,
    required this.onAutoScrollInterrupt,
    required this.isDisposed,
  });

  final VoidCallback onChanged;
  final VoidCallback onAutoScrollInterrupt;
  final bool Function() isDisposed;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  Timer? _inlineSearchDebounce;

  var _searchBarVisible = false;
  var _inlineSearchQuery = '';
  var _appliedInlineSearchQuery = '';
  var _searchCaseSensitive = false;
  var _searchWholeWord = false;
  var _searchRegex = false;
  var _searchCurrentMatchIndex = 0;
  String? _selectedSearchText;

  List<int>? _cachedSearchMatchIndices;
  String _cacheQuery = '';
  bool _cacheCaseSensitive = false;
  bool _cacheWholeWord = false;
  bool _cacheRegex = false;
  Set<String> _cacheHiddenColumns = {};
  int _cacheFilteredLength = -1;

  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _searchCaseSensitive;
  bool get searchWholeWord => _searchWholeWord;
  bool get searchRegex => _searchRegex;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  String? get selectedSearchText => _selectedSearchText;
  String get appliedInlineSearchQuery => _appliedInlineSearchQuery;
  String get inlineSearchQuery => _inlineSearchQuery;

  TextSearchPattern get inlineSearchPattern => TextSearchPattern(
    query: _appliedInlineSearchQuery,
    caseSensitive: _searchCaseSensitive,
    wholeWord: _searchWholeWord,
    regex: _searchRegex,
  );

  bool get inlineSearchHasError => inlineSearchPattern.hasError;
  String? get inlineSearchErrorText => inlineSearchPattern.errorText;

  void toggleSearchBar() {
    if (_searchBarVisible) {
      closeSearchBar();
    } else {
      openSearchBar();
    }
  }

  void openSearchBar({String? query}) {
    _inlineSearchDebounce?.cancel();
    onAutoScrollInterrupt();

    if (query != null) {
      _setInlineSearchQuery(query, applyImmediately: true);
    }

    if (!_searchBarVisible) {
      _searchBarVisible = true;
      onChanged();
    }

    _focusSearchField();
  }

  void closeSearchBar() {
    if (!_searchBarVisible) return;

    _inlineSearchDebounce?.cancel();
    _searchBarVisible = false;
    _inlineSearchQuery = '';
    _appliedInlineSearchQuery = '';
    searchController.clear();
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    onChanged();
  }

  void activateSearchFromSelection() {
    final selectedText = _selectedSearchText;
    if (selectedText != null) {
      unawaited(Clipboard.setData(ClipboardData(text: selectedText)));
      openSearchBar(query: selectedText);
      return;
    }

    openSearchBar();
  }

  void onInlineSearchChanged(String value) {
    if (value.isNotEmpty) {
      onAutoScrollInterrupt();
    }
    _setInlineSearchQuery(value);
  }

  void setSearchCaseSensitive(bool value) {
    if (_searchCaseSensitive == value) return;
    _searchCaseSensitive = value;
    _applySearchOptionChange();
  }

  void setSearchWholeWord(bool value) {
    if (_searchWholeWord == value) return;
    _searchWholeWord = value;
    _applySearchOptionChange();
  }

  void setSearchRegex(bool value) {
    if (_searchRegex == value) return;
    _searchRegex = value;
    _applySearchOptionChange();
  }

  void onSearchNext(List<int> matches) {
    if (matches.isEmpty) return;
    onAutoScrollInterrupt();
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    onChanged();
  }

  void onSearchPrev(List<int> matches) {
    if (matches.isEmpty) return;
    onAutoScrollInterrupt();
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    onChanged();
  }

  void setSelectedSearchText(String? value) {
    final normalized = value?.trim();
    final nextValue = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_selectedSearchText == nextValue) return;
    _selectedSearchText = nextValue;
    onChanged();
  }

  List<int> searchMatchIndices({
    required List<LogEntry> filteredLogs,
    required Set<String> hiddenColumns,
  }) {
    if (_cachedSearchMatchIndices != null &&
        _cacheQuery == _appliedInlineSearchQuery &&
        _cacheCaseSensitive == _searchCaseSensitive &&
        _cacheWholeWord == _searchWholeWord &&
        _cacheRegex == _searchRegex &&
        _cacheHiddenColumns.length == hiddenColumns.length &&
        _cacheHiddenColumns.containsAll(hiddenColumns) &&
        _cacheFilteredLength == filteredLogs.length) {
      return _cachedSearchMatchIndices!;
    }

    _cacheQuery = _appliedInlineSearchQuery;
    _cacheCaseSensitive = _searchCaseSensitive;
    _cacheWholeWord = _searchWholeWord;
    _cacheRegex = _searchRegex;
    _cacheHiddenColumns = Set.of(hiddenColumns);
    _cacheFilteredLength = filteredLogs.length;
    _cachedSearchMatchIndices = _computeSearchMatches(
      filteredLogs,
      hiddenColumns,
    );
    return _cachedSearchMatchIndices!;
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    if (matches.isEmpty) return -1;
    return matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];
  }

  void invalidateSearchMatches() {
    _cachedSearchMatchIndices = null;
  }

  void dispose() {
    _inlineSearchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDisposed()) return;
      searchFocusNode.requestFocus();
      searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: searchController.text.length,
      );
    });
  }

  void _setInlineSearchQuery(String value, {bool applyImmediately = false}) {
    _inlineSearchQuery = value;
    _searchCurrentMatchIndex = 0;

    if (searchController.text != value) {
      searchController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    _inlineSearchDebounce?.cancel();
    if (applyImmediately) {
      _appliedInlineSearchQuery = value;
      invalidateSearchMatches();
      onChanged();
      return;
    }

    onChanged();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (isDisposed()) return;
      _appliedInlineSearchQuery = value;
      invalidateSearchMatches();
      onChanged();
    });
  }

  void _applySearchOptionChange() {
    onAutoScrollInterrupt();
    _inlineSearchDebounce?.cancel();
    _appliedInlineSearchQuery = _inlineSearchQuery;
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    onChanged();
  }

  List<int> _computeSearchMatches(
    List<LogEntry> items,
    Set<String> hiddenColumns,
  ) {
    final pattern = inlineSearchPattern;
    if (!pattern.isActive || !pattern.isValid) return [];

    final visibleColumns = LogColumn.values
        .where((column) => !hiddenColumns.contains(column.name))
        .toList();

    final result = <int>[];
    for (var index = 0; index < items.length; index++) {
      final log = items[index];
      if (log.isSpecialEntry) {
        if (pattern.matches(log.specialSearchableText)) {
          result.add(index);
        }
        continue;
      }
      for (final column in visibleColumns) {
        if (pattern.matches(_logColumnValue(log, column))) {
          result.add(index);
          break;
        }
      }
    }
    return result;
  }

  String _logColumnValue(LogEntry log, LogColumn column) => switch (column) {
    LogColumn.timestamp => log.timestamp,
    LogColumn.pid => log.packageName ?? log.processName ?? log.pid,
    LogColumn.tid => log.tid,
    LogColumn.level => log.isSpecialEntry ? log.typeLabel : log.level,
    LogColumn.tag => log.tag,
    LogColumn.message => log.message,
  };
}
