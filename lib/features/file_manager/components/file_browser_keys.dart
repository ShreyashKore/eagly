import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../file_manager_controller.dart';
import 'file_context_menu.dart';

/// Keyboard control of a file listing, shared by the list and grid views:
/// arrows move the selection ([columns] at a time vertically in a grid),
/// Home/End jump to either end, Enter or ⌘↓ opens a folder, Backspace or ⌘↑
/// goes up, ⌘[ goes back, Delete or ⌘⌫ deletes, F2 renames and Esc clears
/// the filter, then the selection. Bound with both ⌘ and Ctrl, like the
/// other panes' shortcuts.
///
/// Clicking the listing focuses it, so the keys work straight after a
/// click. After a move, the row carrying [revealKey] is scrolled into view.
class const FileBrowserKeys({
  super.key,
  required final FileManagerController controller,
  required final FileManagerActions actions,
  required final GlobalKey revealKey,
  final FocusNode? focusNode,
  final int columns = 1,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<FileBrowserKeys> createState() => _FileBrowserKeysState();
}

class _FileBrowserKeysState extends State<FileBrowserKeys> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  FileManagerController get _controller => widget.controller;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _move(int delta) {
    _controller.moveSelection(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _jump({required bool toEnd}) {
    final reachable = _controller.reachableEntries;
    if (reachable.isEmpty) return;
    _controller.selectEntry(toEnd ? reachable.last : reachable.first);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Scrolls the selected row into view, the least distance needed. A row
  /// that is not built (scrolled far off) is left alone — every move is to a
  /// neighbour, which the list's cache extent keeps built.
  void _reveal() {
    final context = widget.revealKey.currentContext;
    if (context == null) return;
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ]) {
      Scrollable.ensureVisible(context, alignmentPolicy: policy);
    }
  }

  void _whenSelected(void Function() action) {
    if (_controller.selectedEntry != null && !_controller.isBusy) action();
  }

  void _escape() {
    if (_controller.isFiltered) {
      _controller.setFilterText('');
    } else {
      _controller.selectEntry(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = widget.columns;
    final actions = widget.actions;
    final controller = _controller;
    void up() {
      if (!controller.isBusy) controller.navigateUp();
    }

    void back() {
      if (!controller.isBusy) controller.navigateBack();
    }

    void open() => _whenSelected(controller.openSelected);
    // Capabilities are checked when the key is pressed, so building the
    // listing never asks the file system.
    void delete() {
      if (controller.supportsDelete) {
        _whenSelected(() => actions.onDelete(controller.selectedEntry!));
      }
    }

    void rename() {
      if (controller.supportsRename) {
        _whenSelected(() => actions.onRename(controller.selectedEntry!));
      }
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(columns),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-columns),
      if (columns > 1) ...{
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(-1),
      },
      const SingleActivator(LogicalKeyboardKey.home): () => _jump(toEnd: false),
      const SingleActivator(LogicalKeyboardKey.end): () => _jump(toEnd: true),
      const SingleActivator(LogicalKeyboardKey.enter): open,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): open,
      const SingleActivator(LogicalKeyboardKey.backspace): up,
      const SingleActivator(LogicalKeyboardKey.delete): delete,
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
      const SingleActivator(LogicalKeyboardKey.f2): rename,
      for (final meta in const [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.arrowDown,
          meta: meta,
          control: !meta,
        ): open,
        SingleActivator(LogicalKeyboardKey.arrowUp, meta: meta, control: !meta):
            up,
        SingleActivator(
          LogicalKeyboardKey.bracketLeft,
          meta: meta,
          control: !meta,
        ): back,
        SingleActivator(
          LogicalKeyboardKey.backspace,
          meta: meta,
          control: !meta,
        ): delete,
      },
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _focusNode,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_focusNode.hasFocus) _focusNode.requestFocus();
          },
          child: widget.child,
        ),
      ),
    );
  }
}
