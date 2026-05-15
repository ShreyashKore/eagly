import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../../data/log_entry.dart';

class LogTabSelectionController extends ChangeNotifier {
  var _rowSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};
  int? _rowSelectionAnchorIndex;

  bool get rowSelectionMode => _rowSelectionMode;
  Set<int> get selectedRowIndices => Set.unmodifiable(_selectedRowIndices);
  bool get hasSelectedRows => _selectedRowIndices.isNotEmpty;
  int get selectedRowCount => _selectedRowIndices.length;
  int? get rowSelectionAnchorIndex => _rowSelectionAnchorIndex;

  void toggleRowSelectionMode() {
    setRowSelectionMode(!rowSelectionMode);
  }

  void setRowSelectionMode(bool value) {
    if (_rowSelectionMode == value) return;

    _rowSelectionMode = value;
    if (!value) {
      clearSelectedRows(notify: false);
    }
    notifyListeners();
  }

  bool isRowSelected(int filteredIndex) {
    return _selectedRowIndices.contains(filteredIndex);
  }

  bool? beginRowSelectionGesture(
    int filteredIndex,
    List<LogEntry> filteredSnapshot, {
    bool shiftPressed = false,
  }) {
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) {
      return null;
    }

    if (shiftPressed) {
      selectRowRangeTo(filteredIndex, filteredSnapshot);
      return null;
    }

    final shouldSelect = !_selectedRowIndices.contains(filteredIndex);
    final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
    _rowSelectionAnchorIndex = filteredIndex;
    final changed = shouldSelect
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed || anchorChanged) {
      notifyListeners();
    }
    return shouldSelect;
  }

  void setRowSelected(
    int filteredIndex,
    bool selected,
    List<LogEntry> filteredSnapshot,
  ) {
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) {
      return;
    }

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) {
      notifyListeners();
    }
  }

  void setSelectedRows(Set<int> indices, List<LogEntry> filteredSnapshot) {
    final next = indices
        .where((index) => _isSelectableFilteredIndex(index, filteredSnapshot))
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectRowRangeTo(int filteredIndex, List<LogEntry> filteredSnapshot) {
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) return;

    if (_rowSelectionAnchorIndex == null) {
      final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
      _rowSelectionAnchorIndex = filteredIndex;
      final changed = _selectedRowIndices.add(filteredIndex);
      if (changed || anchorChanged) {
        notifyListeners();
      }
      return;
    }

    final start = math.min(_rowSelectionAnchorIndex!, filteredIndex);
    final end = math.max(_rowSelectionAnchorIndex!, filteredIndex);
    var changed = false;
    for (var index = start; index <= end; index++) {
      if (!_isSelectableFilteredIndex(index, filteredSnapshot)) {
        continue;
      }
      changed = _selectedRowIndices.add(index) || changed;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void clearSelectedRows({bool notify = true}) {
    final changed =
        _selectedRowIndices.isNotEmpty || _rowSelectionAnchorIndex != null;
    if (!changed) return;
    _selectedRowIndices.clear();
    _rowSelectionAnchorIndex = null;
    if (notify) {
      notifyListeners();
    }
  }

  bool _isSelectableFilteredIndex(int filteredIndex, List<LogEntry> snapshot) {
    return filteredIndex >= 0 &&
        filteredIndex < snapshot.length &&
        snapshot[filteredIndex].isUserSelectable;
  }
}

