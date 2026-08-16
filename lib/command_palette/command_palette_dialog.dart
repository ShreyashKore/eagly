import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import 'command_palette_item.dart';

/// Opens the global command palette: a VS Code–style search-everything
/// overlay listing every command the app currently exposes.
///
/// [itemsBuilder] is re-run whenever [listenable] notifies, so the list of
/// commands (and their labels/availability) stays live while the palette is
/// open — e.g. pausing capture from elsewhere flips "Pause Capture" to
/// "Resume Capture" without closing and reopening the palette.
Future<void> showCommandPalette({
  required BuildContext context,
  required List<CommandPaletteItem> Function() itemsBuilder,
  required Listenable listenable,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => CommandPaletteDialog(
      itemsBuilder: itemsBuilder,
      listenable: listenable,
    ),
  );
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({
    super.key,
    required this.itemsBuilder,
    required this.listenable,
  });

  final List<CommandPaletteItem> Function() itemsBuilder;
  final Listenable listenable;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  late final FocusNode _fieldFocusNode = FocusNode(onKeyEvent: _handleKey);
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CommandPaletteItem> _all = const [];
  List<CommandPaletteItem> _filtered = const [];
  List<GlobalKey> _itemKeys = const [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _all = widget.itemsBuilder();
    _applyFilter('');
    widget.listenable.addListener(_onSourceChanged);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onSourceChanged);
    _fieldFocusNode.dispose();
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSourceChanged() {
    if (!mounted) return;
    setState(() {
      _all = widget.itemsBuilder();
      _applyFilter(_queryController.text, resetSelection: false);
    });
  }

  void _applyFilter(String query, {bool resetSelection = true}) {
    _filtered = _all
        .where((item) => item.matches(query.trim()))
        .toList(growable: false);
    _itemKeys = List.generate(_filtered.length, (_) => GlobalKey());
    if (resetSelection || _selectedIndex >= _filtered.length) {
      _selectedIndex = 0;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _runSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _filtered.length;
      if (_selectedIndex < 0) _selectedIndex += _filtered.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedIndex >= _itemKeys.length) return;
      final itemContext = _itemKeys[_selectedIndex].currentContext;
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void _runSelected() {
    if (_selectedIndex < 0 || _selectedIndex >= _filtered.length) return;
    _run(_filtered[_selectedIndex]);
  }

  void _run(CommandPaletteItem item) {
    Navigator.of(context).pop();
    item.run();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Align(
      alignment: const Alignment(0, -0.42),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 12,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: media.size.width - 64,
            maxHeight: media.size.height * 0.6,
          ),
          child: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          focusNode: _fieldFocusNode,
                          autofocus: true,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search commands…',
                            isDense: true,
                          ),
                          style: theme.textTheme.bodyLarge,
                          onChanged: (value) =>
                              setState(() => _applyFilter(value)),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                Flexible(
                  child: _filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No matching commands.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _buildList(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    String? lastCategory;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final item = _filtered[index];
        final showHeader = item.category != lastCategory;
        lastCategory = item.category;
        final tile = _CommandTile(
          key: _itemKeys[index],
          item: item,
          selected: index == _selectedIndex,
          onTap: () => _run(item),
          onHover: () => setState(() => _selectedIndex = index),
        );
        if (!showHeader) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                item.category.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            tile,
          ],
        );
      },
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CommandPaletteItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: foreground),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : null,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.subtitle != null)
                        Text(
                          item.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground.withValues(alpha: 0.8),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (item.shortcutLabel != null) ...[
                  const Gap(8),
                  Text(
                    item.shortcutLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: foreground.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
