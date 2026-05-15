import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/log_column.dart';
import '../../../data/log_entry.dart';
import '../../../utils/text_search_pattern.dart';

class LogTabSearchController extends ChangeNotifier {
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  Timer? _inlineSearchDebounce;

  var _searchBarVisible = false;
  var _inlineSearch = const TextSearchConfig();
  var _appliedInlineSearch = const TextSearchConfig();
  var _searchCurrentMatchIndex = 0;
  String? _selectedSearchText;

  List<int>? _cachedSearchMatchIndices;
  TextSearchConfig _smCacheSearch = const TextSearchConfig();
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;
  int? _smCacheFilteredFirstId;
  int? _smCacheFilteredLastId;

  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _inlineSearch.caseSensitive;
  bool get searchWholeWord => _inlineSearch.wholeWord;
  bool get searchRegex => _inlineSearch.regex;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  String? get selectedSearchText => _selectedSearchText;
  String get appliedInlineSearchQuery => _appliedInlineSearch.query;
  String get inlineSearchQuery => _inlineSearch.query;
  TextSearchConfig get inlineSearch => _inlineSearch;
  TextSearchConfig get appliedInlineSearch => _appliedInlineSearch;
  TextSearchPattern get inlineSearchPattern =>
      TextSearchPattern.fromConfig(_appliedInlineSearch);
  bool get inlineSearchHasError => inlineSearchPattern.hasError;
  String? get inlineSearchErrorText => inlineSearchPattern.errorText;

  void toggleSearchBar({required VoidCallback disableAutoScroll}) {
    if (_searchBarVisible) {
      closeSearchBar();
    } else {
      openSearchBar(disableAutoScroll: disableAutoScroll);
    }
  }

  void openSearchBar({
    String? query,
    required VoidCallback disableAutoScroll,
  }) {
    _inlineSearchDebounce?.cancel();
    disableAutoScroll();

    if (query != null) {
      updateInlineSearch(
        _inlineSearch.copyWith(query: query),
        applyImmediately: true,
        disableAutoScroll: disableAutoScroll,
      );
    }

    if (_searchBarVisible) return;
    _searchBarVisible = true;
    notifyListeners();
  }

  void closeSearchBar() {
    if (!_searchBarVisible) return;

    _inlineSearchDebounce?.cancel();
    _searchBarVisible = false;
    _inlineSearch = _inlineSearch.copyWith(query: '');
    _appliedInlineSearch = _appliedInlineSearch.copyWith(query: '');
    searchController.clear();
    invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    notifyListeners();
  }

  void onInlineSearchChanged(
    String value, {
    required VoidCallback disableAutoScroll,
  }) {
    updateInlineSearch(
      _inlineSearch.copyWith(query: value),
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchCaseSensitive(
    bool value, {
    required VoidCallback disableAutoScroll,
  }) {
    updateInlineSearch(
      _inlineSearch.copyWith(caseSensitive: value),
      applyImmediately: true,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchWholeWord(bool value, {required VoidCallback disableAutoScroll}) {
    updateInlineSearch(
      _inlineSearch.copyWith(wholeWord: value),
      applyImmediately: true,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void setSearchRegex(bool value, {required VoidCallback disableAutoScroll}) {
    updateInlineSearch(
      _inlineSearch.copyWith(regex: value),
      applyImmediately: true,
      disableAutoScroll: disableAutoScroll,
    );
  }

  void onSearchNext(List<int> matches, {required VoidCallback disableAutoScroll}) {
    if (matches.isEmpty) return;
    disableAutoScroll();
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    notifyListeners();
  }

  void onSearchPrev(List<int> matches, {required VoidCallback disableAutoScroll}) {
    if (matches.isEmpty) return;
    disableAutoScroll();
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    notifyListeners();
  }

  void setSelectedSearchText(String? value) {
    final normalized = value?.trim();
    final nextValue = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_selectedSearchText == nextValue) return;
    _selectedSearchText = nextValue;
    notifyListeners();
  }

  void updateInlineSearch(
    TextSearchConfig value, {
    bool applyImmediately = false,
    required VoidCallback disableAutoScroll,
  }) {
    final optionsChanged =
        value.caseSensitive != _inlineSearch.caseSensitive ||
        value.wholeWord != _inlineSearch.wholeWord ||
        value.regex != _inlineSearch.regex;
    final queryChanged = value.query != _inlineSearch.query;
    final appliedChanged = value != _appliedInlineSearch;
    if (!queryChanged &&
        !optionsChanged &&
        (!applyImmediately || !appliedChanged)) {
      return;
    }

    if (value.query.isNotEmpty || optionsChanged) {
      disableAutoScroll();
    }

    _inlineSearch = value;
    _searchCurrentMatchIndex = 0;

    if (searchController.text != value.query) {
      searchController.value = TextEditingValue(
        text: value.query,
        selection: TextSelection.collapsed(offset: value.query.length),
      );
    }

    _inlineSearchDebounce?.cancel();
    if (applyImmediately || optionsChanged) {
      _appliedInlineSearch = value;
      invalidateSearchMatches();
      notifyListeners();
      return;
    }

    notifyListeners();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      _appliedInlineSearch = value;
      invalidateSearchMatches();
      notifyListeners();
    });
  }

  List<int> searchMatchIndicesFor(
    List<LogEntry> filteredLogs,
    Set<String> hiddenColumns,
  ) {
    final firstId = filteredLogs.isEmpty ? null : filteredLogs.first.id;
    final lastId = filteredLogs.isEmpty ? null : filteredLogs.last.id;
    if (_cachedSearchMatchIndices != null &&
        _smCacheSearch == _appliedInlineSearch &&
        _smCacheHiddenCols.length == hiddenColumns.length &&
        _smCacheHiddenCols.containsAll(hiddenColumns) &&
        _smCacheFilteredLen == filteredLogs.length &&
        _smCacheFilteredFirstId == firstId &&
        _smCacheFilteredLastId == lastId) {
      return _cachedSearchMatchIndices!;
    }

    _smCacheSearch = _appliedInlineSearch;
    _smCacheHiddenCols = Set.of(hiddenColumns);
    _smCacheFilteredLen = filteredLogs.length;
    _smCacheFilteredFirstId = firstId;
    _smCacheFilteredLastId = lastId;
    _cachedSearchMatchIndices = _computeSearchMatches(filteredLogs, hiddenColumns);
    return _cachedSearchMatchIndices!;
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    if (matches.isEmpty) return -1;
    return matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];
  }

  void invalidateSearchMatches() {
    _cachedSearchMatchIndices = null;
  }

  List<int> _computeSearchMatches(
    List<LogEntry> items,
    Set<String> hiddenColumns,
  ) {
    final pattern = inlineSearchPattern;
    if (!pattern.isActive || !pattern.isValid) return [];

    final visibleColumns = LogColumn.values
        .where((column) => !hiddenColumns.contains(column.name))
        .toList(growable: false);

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
        if (pattern.matches(log.valueForColumn(column))) {
          result.add(index);
          break;
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    _inlineSearchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }
}

