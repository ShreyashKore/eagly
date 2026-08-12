import 'package:flutter/material.dart';

/// Column-visibility button — pinned top-right over the log viewer header.
class ColumnVisibilityButton extends StatelessWidget {
  const ColumnVisibilityButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Tooltip(
        message: 'Column visibility',
        child: InkWell(
          onTap: onTap,
          child: Icon(
            Icons.view_column_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
