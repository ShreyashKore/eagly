import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/layout_selectors.dart';
import '../layout_inspector_controller.dart';
import '../../../presentation/components/snack_bars.dart';

/// Everything known about the selected node: the accessibility node's
/// fields, the View it was matched to, and selectors to copy. A click on a
/// value copies it.
class const LayoutNodeDetails({
  super.key,
  required final LayoutInspectorController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = controller.selected;
    final snapshot = controller.snapshot;
    if (node == null || snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Click the screen or a row to inspect a node.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.eaglyTheme.secondaryTextColor),
          ),
        ),
      );
    }

    final bounds = node.bounds;
    final density = snapshot.densityDpi;
    final size = '${_i(bounds.width)} × ${_i(bounds.height)} px';
    final sizeDp = density == null
        ? null
        : '${_i(bounds.width * 160 / density)} × '
              '${_i(bounds.height * 160 / density)} dp';
    final view = node.view;

    final rows = <(String, String?)>[
      ('Class', node.className),
      if (view != null) ('View class', view.className),
      ('Resource id', node.resourceId),
      if (view?.resourceName case final name?
          when name.split(':id/').last != node.resourceEntry)
        ('View id', name),
      ('Text', node.text),
      ('Content description', node.contentDescription),
      ('Hint', node.hint),
      ('State', node.stateDescription),
      ('Pane title', node.paneTitle),
      ('Package', node.packageName),
      (
        'Bounds',
        '[${_i(bounds.left)},${_i(bounds.top)}]'
            '[${_i(bounds.right)},${_i(bounds.bottom)}]',
      ),
      ('Size', sizeDp == null ? size : '$size · $sizeDp'),
      if (view != null && view.visibility != 'visible')
        ('Visibility', view.visibility),
      ('Window', snapshot.windowOf(node)?.label),
    ];
    final flags = {
      ...node.flags.where((flag) => flag != 'visible' && flag != 'important'),
      if (!node.isVisible) 'offscreen',
      ...?view?.flagNames.where(
        (flag) => !node.flags.contains(flag) && flag != 'willNotDraw',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  node.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _CopyAsButton(selectors: selectorsFor(node, snapshot)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final (label, value) in rows)
                if (value != null && value.isNotEmpty)
                  _PropertyRow(label: label, value: value),
              if (flags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final flag in flags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Text(flag, style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _i(double value) => value.round().toString();
}

class const _PropertyRow({
  required final String label,
  required final String value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => copyWithToast(context, value, '$label copied'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: context.scaled(128),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.eaglyTheme.secondaryTextColor,
                ),
              ),
            ),
            Expanded(
              child: Tooltip(
                message: 'Click to copy',
                waitDuration: const Duration(milliseconds: 600),
                child: Text(value, style: theme.textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _CopyAsButton({required final List<LayoutSelector> selectors})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LayoutSelector>(
      tooltip: 'Copy a selector for this node',
      onSelected: (selector) => copyWithToast(
        context,
        selector.value,
        '${selector.label} selector copied',
      ),
      itemBuilder: (context) => [
        for (final selector in selectors)
          PopupMenuItem(
            value: selector,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selector.label),
                Text(
                  selector.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: context.eaglyTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_outlined, size: context.scaled(16)),
            const SizedBox(width: 4),
            const Text('Copy as'),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
