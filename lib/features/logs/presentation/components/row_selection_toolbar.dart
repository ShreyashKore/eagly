import 'package:flutter/material.dart';

/// Floating pill shown at the bottom of the log viewer while rows are
/// selected: the selection count plus a Clear button.
class RowSelectionToolbar extends StatelessWidget {
  const RowSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final count = selectedCount;
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          key: const ValueKey('row-selection-toolbar'),
          elevation: 10,
          color: theme.colorScheme.surfaceContainerHighest,
          shadowColor: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    count == 1 ? '1 row selected' : '$count rows selected',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onClear,
                  icon: const Icon(Icons.deselect_outlined),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
