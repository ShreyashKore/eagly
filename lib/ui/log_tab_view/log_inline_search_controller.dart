import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/log_column.dart';
import '../../data/log_entry.dart';
import '../../utils/text_search_pattern.dart';

/// Manages the inline (find-in-logs) search bar: visibility, query, options,
/// match indices, and navigation.
class LogInlineSearchController extends ChangeNotifier {
  LogInlineSearchController({
    required Set<String> Function() hiddenColumnsProvider,
    required List<LogEntry> Function() filteredLogsProvider,
  })  : _hiddenColumnsProvider = hiddenColumnsProvider,
        _filteredLogsProvider = filteredLogsProvider;

  final Set<String> Function() _hiddenColumnsProvider;
  final List<LogEntry> Function() _filteredLogsProvider;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  Timer? _debounce;
  bool _disposed = false;

  var _searchBarVisible = false;
  var _inlineSearchQuery = '';
  var _appliedInlineSearchQuery = '';
  var _searchCaseSensitive = false;
  var _searchWholeWord = false;
  var _searchRegex = false;
  var _searchCurrentMatchIndex = 0;
  String? _selectedSearchText;

  List<int>? _cachedMatchIndices;
  String _smCacheQuery = '';
  bool _smCacheCaseSensitive = false;
  bool _smCacheWholeWord = false;
  bool _smCacheRegex = false;
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

  /// Invoked when the search bar is opened and auto-scroll should be disabled.
  VoidCallback? onDisableAutoScroll;

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

  List<int> get searchMatchIndices {
    final filtered = _filteredLogsProvider();
    final hiddenCols = _hiddenColumnsProvider();

    if (_cachedMatchIndices != null &&
        _smCacheQuery == _appliedInlineSearchQuery &&
        _smCacheCaseSensitive == _searchCaseSensitive &&
        _smCacheWholeWord == _searchWholeWord &&
        _smCacheRegex == _searchRegex &&
        _smCacheHiddenCols.length == hiddenCols.length &&
        _smCacheHiddenCols.containsAll(hiddenCols) &&
        _smCacheFilteredLen == filtered.length) {
      return _cachedMatchIndices!;
    }

    _smCacheQuery = _appliedInlineSearchQuery;
    _smCacheCaseSensitive = _searchCaseSensitive;
    _smCacheWholeWord = _searchWholeWord;
    _smCacheRegex = _searchRegex;
    _smCacheHiddenCols = Set.of(hiddenCols);
    _smCacheFilteredLen = filtered.length;
    _cachedMatchIndices = _computeSearchMatches(filtered);
    return _cachedMatchIndices!;
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    if (matches.isEmpty) return -1;
    return matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];
  }

  void invalidateSearchMatches() {
    _cachedMatchIndices = null;
  }

  void setSelectedSearchText(String? value) {
    final normalized = value?.trim();
    final nextValue =
        normalized == null || normalized.isEmpty ? null : normalized;
    if (_selectedSearchText == nextValue) return;
    _selectedSearchText = nextValue;
    notifyListeners();
  }

  void toggleSearchBar() {
    if (_searchBarVisible) {
      closeSearchBar();
    } else {
      openSearchBar();
    }
  }

  void openSearchBar({String? query}) {
    _debounce?.cancel();
    onDisableAutoScroll?.call();

    if (query != null) {
      _setInlineSearchQuery(query, applyImmediately: true);
    }

    if (!_searchBarVisible) {
      _searchBarVisible = true;
      notifyListeners();
    }

    _focusSearchField();
  }

  void closeSearchBar() {
    if (!_searchBarVisible) return;

    _debounce?.cancel();
    _searchBarVisible = false;
    _inlineSearchQuery = '';
    _appliedInlineSearchQuery = '';
    searchController.clear();
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    notifyListeners();
  }

  void activateSearchFromSelection() {
    final selectedText = _selectedSearchText;
    if (selectedText != null) {
      // ignore: unawaited_futures
      Clipboard.setData(ClipboardData(text: selectedText));
      openSearchBar(query: selectedText);
      return;
    }
    openSearchBar();
  }

  void onInlineSearchChanged(String value) {
    if (value.isNotEmpty) {
      onDisableAutoScroll?.call();
    }
    _setInlineSearchQuery(value);
  }

  void setSearchCaseSensitive(bool value) {
    if (_searchCaseSensitive == value) return;
    onDisableAutoScroll?.call();
    _debounce?.cancel();
    _searchCaseSensitive = value;
    _appliedInlineSearchQuery = _inlineSearchQuery;
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    notifyListeners();
  }

  void setSearchWholeWord(bool value) {
    if (_searchWholeWord == value) return;
    onDisableAutoScroll?.call();
    _debounce?.cancel();
    _searchWholeWord = value;
    _appliedInlineSearchQuery = _inlineSearchQuery;
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    notifyListeners();
  }

  void setSearchRegex(bool value) {
    if (_searchRegex == value) return;
    onDisableAutoScroll?.call();
    _debounce?.cancel();
    _searchRegex = value;
    _appliedInlineSearchQuery = _inlineSearchQuery;
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    notifyListeners();
  }

  void onSearchNext() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    onDisableAutoScroll?.call();
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    notifyListeners();
  }

  void onSearchPrev() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    onDisableAutoScroll?.call();
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    notifyListeners();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
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

    _debounce?.cancel();
    if (applyImmediately) {
      _appliedInlineSearchQuery = value;
      invalidateSearchMatches();
      notifyListeners();
      return;
    }

    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedInlineSearchQuery = value;
      invalidateSearchMatches();
      notifyListeners();
    });
  }

  String _logColumnValue(LogEntry log, LogColumn column) => switch (column) {
        LogColumn.timestamp => log.timestamp,
        LogColumn.pid => log.packageName ?? log.processName ?? log.pid,
        LogColumn.tid => log.tid,
        LogColumn.level => log.isSpecialEntry ? log.typeLabel : log.level,
        LogColumn.tag => log.tag,
        LogColumn.message => log.message,
      };

  List<int> _computeSearchMatches(List<LogEntry> items) {
    final pattern = inlineSearchPattern;
    if (!pattern.isActive || !pattern.isValid) return [];

    final hiddenCols = _hiddenColumnsProvider();
    final visibleColumns = LogColumn.values
        .where((column) => !hiddenCols.contains(column.name))
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

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }
}

