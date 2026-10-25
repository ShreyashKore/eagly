import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/layout_snapshot.dart';
import '../layout_inspector_controller.dart';

/// The captured tree, one row per window and node. Rows have one height, so
/// a node picked on the screenshot can be scrolled to by its index.
class const LayoutTreeView({
  super.key,
  required final LayoutInspectorController controller,
}) extends StatefulWidget {
  @override
  State<LayoutTreeView> createState() => _LayoutTreeViewState();
}

class _LayoutTreeViewState extends State<LayoutTreeView> {
  final ScrollController _scroll = ScrollController();
  String? _revealedKey;

  LayoutInspectorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_revealSelection);
    // A pane reopened over an earlier selection shows it too.
    _revealSelection();
  }

  @override
  void didUpdateWidget(LayoutTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_revealSelection);
      controller.addListener(_revealSelection);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_revealSelection);
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls a newly selected node into view, once per selection, so
  /// scrolling away from it afterwards isn't undone by the next refresh.
  void _revealSelection() {
    final key = controller.selected?.key;
    if (key == null || key == _revealedKey) return;
    _revealedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final rows = controller.treeRows;
      final index = rows.indexWhere(
        (row) => row is LayoutNodeRow && row.node.key == key,
      );
      if (index < 0) return;
      final extent = context.scaled(_rowHeight);
      final top = index * extent;
      final position = _scroll.position;
      final viewport = position.viewportDimension;
      if (top >= position.pixels &&
          top + extent <= position.pixels + viewport) {
        return;
      }
      _scroll.jumpTo((top - viewport / 3).clamp(0.0, position.maxScrollExtent));
    });
  }

  static const double _rowHeight = 24;

  @override
  Widget build(BuildContext context) {
    final rows = controller.treeRows;
    final searching = controller.query.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TreeSearchField(controller: controller),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    searching ? 'No node matches.' : 'Nothing captured yet.',
                    style: TextStyle(
                      color: context.eaglyTheme.secondaryTextColor,
                    ),
                  ),
                )
              : MouseRegion(
                  onExit: (_) => controller.hover(null),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: rows.length,
                    itemExtent: context.scaled(_rowHeight),
                    itemBuilder: (context, index) => switch (rows[index]) {
                      LayoutWindowRow(:final window) => _WindowRow(
                        window: window,
                      ),
                      LayoutNodeRow(:final node, :final depth) => _NodeRow(
                        controller: controller,
                        node: node,
                        depth: depth,
                        searching: searching,
                      ),
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class const _WindowRow({required final LayoutWindow window})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            window.type == 'inputMethod'
                ? Icons.keyboard_outlined
                : Icons.web_asset,
            size: context.scaled(14),
            color: context.eaglyTheme.secondaryTextColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              window.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.eaglyTheme.secondaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _NodeRow({
  required final LayoutInspectorController controller,
  required final LayoutNode node,
  required final int depth,
  required final bool searching,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;
    final selected = controller.selected == node;
    final hovered = controller.hovered == node;
    final match = searching && controller.matches(node);
    final hasChildren = node.children.isNotEmpty;
    final collapsed = controller.isCollapsed(node);
    final dimmed = !node.isVisible;

    final className = node.view?.shortClassName ?? node.shortClassName;
    final entry = node.resourceEntry;
    final words = node.text ?? node.contentDescription;
    final base = theme.textTheme.bodySmall!;

    return MouseRegion(
      onEnter: (_) => controller.hover(node),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.select(node),
        onDoubleTap: hasChildren
            ? () => controller.toggleCollapsed(node)
            : null,
        child: Container(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : hovered
              ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
              : null,
          padding: EdgeInsets.only(left: 4 + depth * context.scaled(12)),
          child: Row(
            children: [
              SizedBox(
                width: context.scaled(18),
                child: hasChildren && !searching
                    ? AppIconButton(
                        tooltip: collapsed ? 'Expand' : 'Collapse',
                        icon: collapsed
                            ? Icons.chevron_right
                            : Icons.expand_more,
                        iconSize: 14,
                        padding: 1,
                        onPressed: () => controller.toggleCollapsed(node),
                      )
                    : null,
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: className,
                        style: TextStyle(
                          fontWeight: match ? FontWeight.w700 : null,
                          backgroundColor: match
                              ? eagly.searchMatchColor
                              : null,
                          color: match ? eagly.searchHighlightForeground : null,
                        ),
                      ),
                      if (entry != null)
                        TextSpan(
                          text: '  #$entry',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      if (words != null)
                        TextSpan(
                          text: '  "${words.replaceAll('\n', ' ')}"',
                          style: TextStyle(color: eagly.secondaryTextColor),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                    color: dimmed ? eagly.tertiaryTextColor : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrows the tree to nodes whose class, id or text contains the query.
/// Esc clears it.
class const _TreeSearchField({
  required final LayoutInspectorController controller,
}) extends StatefulWidget {
  @override
  State<_TreeSearchField> createState() => _TreeSearchFieldState();
}

class _TreeSearchFieldState extends State<_TreeSearchField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.query,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.controller.setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = widget.controller.query.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: context.scaled(30),
        child: CallbackShortcuts(
          bindings: {
            if (hasText)
              const SingleActivator(LogicalKeyboardKey.escape): _clear,
          },
          child: TextField(
            controller: _text,
            onChanged: widget.controller.setQuery,
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find by class, id or text…',
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: hasText
                  ? AppIconButton(
                      tooltip: 'Clear search',
                      iconSize: 14,
                      padding: 4,
                      onPressed: _clear,
                      icon: Icons.close,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ),
    );
  }
}
