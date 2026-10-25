import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// An ordered list of tabs with one selected — what `LogSessionManager` and
/// `TerminalSessionManager` share. Subclasses decide which tabs may close
/// ([canClose]) and how new ones are made; this owns selecting, closing and,
/// on [dispose], disposing them.
abstract class TabListManager<T extends ChangeNotifier> extends ChangeNotifier {
  final List<T> _tabs = [];
  int _selectedIndex = 0;
  bool _disposed = false;

  List<T> get tabs => List.unmodifiable(_tabs);
  int get selectedIndex => _selectedIndex;

  /// The tab at [index], without the copy [tabs] makes.
  @protected
  T tabAt(int index) => _tabs[index];

  @protected
  int get tabCount => _tabs.length;

  @protected
  bool get isDisposed => _disposed;

  /// Whether the tab at [index] may be closed.
  bool canClose(int index);

  /// Appends [tab] and selects it. [notify] is false while a constructor
  /// seeds the first tab, before anyone listens.
  @protected
  void appendTab(T tab, {bool notify = true}) {
    _tabs.add(tab);
    _selectedIndex = _tabs.length - 1;
    if (notify) notifyChanged();
  }

  void selectTab(int index) {
    if (index == _selectedIndex || index < 0 || index >= _tabs.length) return;
    _selectedIndex = index;
    notifyChanged();
  }

  void closeTab(int index) {
    if (!canClose(index)) return;
    _tabs[index].dispose();
    _tabs.removeAt(index);
    _selectedIndex = _selectedIndex.clamp(0, math.max(0, _tabs.length - 1));
    notifyChanged();
  }

  /// [notifyListeners], unless already disposed.
  @protected
  void notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }
}
