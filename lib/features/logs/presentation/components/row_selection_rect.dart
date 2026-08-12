import 'package:flutter/material.dart';

/// Translucent rectangle painted over the rows covered by an in-progress
/// drag selection. Purely visual — pointer events pass through.
class RowSelectionRect extends StatelessWidget {
  const RowSelectionRect({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const ValueKey('row-selection-rect'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
