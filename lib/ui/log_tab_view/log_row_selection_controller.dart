import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../data/log_entry.dart';

/// Manages which rows in the filtered log list are currently selected.
class LogRowSelectionController extends ChangeNotifier {
  LogRowSelectionController({
    required List<LogEntry> Function() filteredLogsProvider,
  }) : _filteredLogsProvider = filteredLogsProvider;

  final List<LogEntry> Function() _filteredLogsProvider;

  var _rowSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};
  int? _rowSelectionAnchorIndex;

  bool get rowSelectionMode => _rowSelectionMode;
  Set<int> get selectedRowIndices => Set.unmodifiable(_selectedRowIndices);
  bool get hasSelectedRows => _selectedRowIndices.isNotEmpty;
  int get selectedRowCount => _selectedRowIndices.length;
  int? get rowSelectionAnchorIndex => _rowSelectionAnchorIndex;

  void toggleRowSelectionMode() => setRowSelectionMode(!_rowSelectionMode);

  void setRowSelectionMode(bool value) {
    if (_rowSelectionMode == value) return;
    _rowSelectionMode = value;
    if (!value) clearSelectedRows(notify: false);
    notifyListeners();
  }

  bool isRowSelected(int filteredIndex) =>
      _selectedRowIndices.contains(filteredIndex);

  /// Returns whether the row at [filteredIndex] will be selected (`true`),
  /// deselected (`false`), or if the index is not selectable (`null`).
  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
  }) {
    if (!_isSelectableFilteredIndex(filteredIndex)) return null;

    if (shiftPressed) {
      selectRowRangeTo(filteredIndex);
      return null;
    }

    final shouldSelect = !_selectedRowIndices.contains(filteredIndex);
    final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
    _rowSelectionAnchorIndex = filteredIndex;
    final changed = shouldSelect
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed || anchorChanged) notifyListeners();
    return shouldSelect;
  }

  void setRowSelected(int filteredIndex, bool selected) {
    if (!_isSelectableFilteredIndex(filteredIndex)) return;
    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) notifyListeners();
  }

  void setSelectedRows(Set<int> indices) {
    final filteredSnapshot = _filteredLogsProvider();
    final next = indices
        .where((index) => _isSelectableFilteredIndex(index, filteredSnapshot))
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) return;

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectRowRangeTo(int filteredIndex) {
    final filteredSnapshot = _filteredLogsProvider();
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) return;

    if (_rowSelectionAnchorIndex == null) {
      final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
      _rowSelectionAnchorIndex = filteredIndex;
      final changed = _selectedRowIndices.add(filteredIndex);
      if (changed || anchorChanged) notifyListeners();
      return;
    }

    final start = math.min(_rowSelectionAnchorIndex!, filteredIndex);
    final end = math.max(_rowSelectionAnchorIndex!, filteredIndex);
    var changed = false;
    for (var index = start; index <= end; index++) {
      if (!_isSelectableFilteredIndex(index, filteredSnapshot)) continue;
      changed = _selectedRowIndices.add(index) || changed;
    }
    if (changed) notifyListeners();
  }

  void clearSelectedRows({bool notify = true}) {
    final changed =
        _selectedRowIndices.isNotEmpty || _rowSelectionAnchorIndex != null;
    if (!changed) return;
    _selectedRowIndices.clear();
    _rowSelectionAnchorIndex = null;
    if (notify) notifyListeners();
  }

  bool _isSelectableFilteredIndex(
    int filteredIndex, [
    List<LogEntry>? snapshot,
  ]) {
    final filteredSnapshot = snapshot ?? _filteredLogsProvider();
    return filteredIndex >= 0 &&
        filteredIndex < filteredSnapshot.length &&
        filteredSnapshot[filteredIndex].isUserSelectable;
  }
}

