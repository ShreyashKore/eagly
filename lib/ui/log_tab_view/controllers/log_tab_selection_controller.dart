import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../data/log_entry.dart';

class LogTabSelectionController {
  LogTabSelectionController({
    required this.onChanged,
    required this.filteredLogsProvider,
  });

  final VoidCallback onChanged;
  final List<LogEntry> Function() filteredLogsProvider;

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
    onChanged();
  }

  bool isRowSelected(int filteredIndex) {
    return _selectedRowIndices.contains(filteredIndex);
  }

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
    if (changed || anchorChanged) {
      onChanged();
    }
    return shouldSelect;
  }

  void setRowSelected(int filteredIndex, bool selected) {
    if (!_isSelectableFilteredIndex(filteredIndex)) return;

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) {
      onChanged();
    }
  }

  void setSelectedRows(Set<int> indices) {
    final filteredSnapshot = filteredLogsProvider();
    final next = indices
        .where((index) => _isSelectableFilteredIndex(index, filteredSnapshot))
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    onChanged();
  }

  void selectRowRangeTo(int filteredIndex) {
    final filteredSnapshot = filteredLogsProvider();
    if (!_isSelectableFilteredIndex(filteredIndex, filteredSnapshot)) return;

    if (_rowSelectionAnchorIndex == null) {
      final anchorChanged = _rowSelectionAnchorIndex != filteredIndex;
      _rowSelectionAnchorIndex = filteredIndex;
      final changed = _selectedRowIndices.add(filteredIndex);
      if (changed || anchorChanged) {
        onChanged();
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
      onChanged();
    }
  }

  void clearSelectedRows({bool notify = true}) {
    final changed =
        _selectedRowIndices.isNotEmpty || _rowSelectionAnchorIndex != null;
    if (!changed) return;
    _selectedRowIndices.clear();
    _rowSelectionAnchorIndex = null;
    if (notify) {
      onChanged();
    }
  }

  List<int> selectionTargetIndicesForCopy(int? clickedFilteredIndex) {
    final filteredSnapshot = filteredLogsProvider();
    final selectedIndices =
        _selectedRowIndices
            .where(
              (index) => _isSelectableFilteredIndex(index, filteredSnapshot),
            )
            .toList()
          ..sort();

    if (clickedFilteredIndex == null) {
      return selectedIndices;
    }

    final clickedIsCopyable = _isSelectableFilteredIndex(
      clickedFilteredIndex,
      filteredSnapshot,
    );
    if (!clickedIsCopyable) {
      return selectedIndices;
    }

    if (selectedIndices.isNotEmpty &&
        selectedIndices.contains(clickedFilteredIndex)) {
      return selectedIndices;
    }
    return [clickedFilteredIndex];
  }

  bool _isSelectableFilteredIndex(
    int filteredIndex, [
    List<LogEntry>? snapshot,
  ]) {
    final filteredSnapshot = snapshot ?? filteredLogsProvider();
    return filteredIndex >= 0 &&
        filteredIndex < filteredSnapshot.length &&
        filteredSnapshot[filteredIndex].isUserSelectable;
  }
}
