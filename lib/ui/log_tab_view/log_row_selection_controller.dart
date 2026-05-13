import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/log_entry.dart';

enum LogCopyFormat { messageOnly, timestampAndMessage, fullLine }

class LogRowSelectionController extends ChangeNotifier {
  LogRowSelectionController();

  var _rowSelectionMode = false;
  final Set<int> _selectedRowIndices = <int>{};
  int? _rowSelectionAnchorIndex;

  bool get rowSelectionMode => _rowSelectionMode;
  Set<int> get selectedRowIndices => Set.unmodifiable(_selectedRowIndices);
  bool get hasSelectedRows => _selectedRowIndices.isNotEmpty;
  int get selectedRowCount => _selectedRowIndices.length;
  int? get rowSelectionAnchorIndex => _rowSelectionAnchorIndex;

  void toggleRowSelectionMode() {
    setRowSelectionMode(!_rowSelectionMode);
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

  bool _isSelectableFilteredIndex(
    int filteredIndex, [
    List<LogEntry>? snapshot,
    List<LogEntry> Function()? filteredLogsProvider,
  ]) {
    final filteredSnapshot =
        snapshot ?? filteredLogsProvider?.call() ?? const [];
    return filteredIndex >= 0 &&
        filteredIndex < filteredSnapshot.length &&
        filteredSnapshot[filteredIndex].isUserSelectable;
  }

  bool? beginRowSelectionGesture(
    int filteredIndex, {
    bool shiftPressed = false,
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    if (!_isSelectableFilteredIndex(
      filteredIndex,
      null,
      filteredLogsProvider,
    )) {
      return null;
    }

    if (shiftPressed) {
      selectRowRangeTo(filteredIndex, filteredLogsProvider: filteredLogsProvider);
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
    bool selected, {
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    if (!_isSelectableFilteredIndex(
      filteredIndex,
      null,
      filteredLogsProvider,
    )) {
      return;
    }

    final changed = selected
        ? _selectedRowIndices.add(filteredIndex)
        : _selectedRowIndices.remove(filteredIndex);
    if (changed) {
      notifyListeners();
    }
  }

  void setSelectedRows(
    Set<int> indices, {
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    final filteredSnapshot = filteredLogsProvider();
    final next = indices
        .where(
          (index) => _isSelectableFilteredIndex(index, filteredSnapshot),
        )
        .toSet();
    if (const SetEquality<int>().equals(_selectedRowIndices, next)) {
      return;
    }

    _selectedRowIndices
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectRowRangeTo(
    int filteredIndex, {
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    final filteredSnapshot = filteredLogsProvider();
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
      if (!_isSelectableFilteredIndex(index, filteredSnapshot)) continue;
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

  // --- Copy logic ---

  Future<int> copyAllLogs(Iterable<LogEntry> allLogs) {
    return _copyLogsToClipboard(
      allLogs.where((entry) => entry.isCopyable),
      format: LogCopyFormat.fullLine,
    );
  }

  Future<int> copyRowsForContextMenu({
    required int? clickedFilteredIndex,
    required LogCopyFormat format,
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    final selectedIndices = _selectionTargetIndicesForCopy(
      clickedFilteredIndex,
      filteredLogsProvider,
    );
    return copyFilteredRows(
      selectedIndices,
      format: format,
      filteredLogsProvider: filteredLogsProvider,
    );
  }

  Future<int> copyFilteredRows(
    Iterable<int> filteredIndices, {
    required LogCopyFormat format,
    required List<LogEntry> Function() filteredLogsProvider,
  }) {
    final filteredSnapshot = List<LogEntry>.of(filteredLogsProvider());
    final indices = filteredIndices
        .toSet()
        .where((index) => index >= 0 && index < filteredSnapshot.length)
        .toList()
      ..sort();

    if (indices.isEmpty) return Future<int>.value(0);

    final entries = [
      for (final index in indices)
        if (filteredSnapshot[index].isCopyable) filteredSnapshot[index],
    ];
    return _copyLogsToClipboard(entries, format: format);
  }

  String formatLogsForClipboard(
    Iterable<LogEntry> entries, {
    required LogCopyFormat format,
  }) {
    return entries
        .map((entry) => _formatLogEntryForCopy(entry, format))
        .join('\n');
  }

  List<int> _selectionTargetIndicesForCopy(
    int? clickedFilteredIndex,
    List<LogEntry> Function() filteredLogsProvider,
  ) {
    final filteredSnapshot = filteredLogsProvider();
    final selectedIndices = _selectedRowIndices
        .where(
          (index) => _isSelectableFilteredIndex(index, filteredSnapshot),
        )
        .toList()
      ..sort();

    if (clickedFilteredIndex == null) return selectedIndices;

    final clickedIsCopyable = _isSelectableFilteredIndex(
      clickedFilteredIndex,
      filteredSnapshot,
    );
    if (!clickedIsCopyable) return selectedIndices;

    if (selectedIndices.isNotEmpty &&
        selectedIndices.contains(clickedFilteredIndex)) {
      return selectedIndices;
    }
    return [clickedFilteredIndex];
  }

  Future<int> _copyLogsToClipboard(
    Iterable<LogEntry> entries, {
    required LogCopyFormat format,
  }) async {
    final snapshot = List<LogEntry>.of(entries);
    if (snapshot.isEmpty) return 0;

    final text = formatLogsForClipboard(snapshot, format: format);
    await Clipboard.setData(ClipboardData(text: text));
    return snapshot.length;
  }

  String _formatLogEntryForCopy(LogEntry log, LogCopyFormat format) {
    return switch (format) {
      LogCopyFormat.messageOnly => log.message,
      LogCopyFormat.timestampAndMessage => '${log.timestamp} ${log.message}',
      LogCopyFormat.fullLine =>
        '${log.timestamp} ${log.packageName ?? log.pid} ${log.tid} ${log.level} ${log.tag}: ${log.message}',
    };
  }
}

