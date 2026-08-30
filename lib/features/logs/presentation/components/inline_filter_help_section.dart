import 'package:eagly/presentation/components/animation_utils.dart';
import 'package:flutter/material.dart';

/// Expandable help panel under the inline filter bar: a syntax cheat-sheet
/// plus tappable chips that append example filter tokens.
class InlineFilterHelpSection extends StatelessWidget {
  const InlineFilterHelpSection({
    super.key,
    required this.visible,
    required this.isIos,
    required this.onAppendToken,
  });

  final bool visible;
  final bool isIos;
  final void Function(String token, {required bool applyImmediately})
  onAppendToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSection(
      visible: visible,
      axis: Axis.vertical,
      child: Container(
        key: const ValueKey('inline-filter-help'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Text(
              'Bare words search the whole log entry. Use key:value for '
              'package, ${isIos ? 'category' : 'tag'}, pid, message, '
              'level, or age (e.g. age:1h). Add =: for an exact match, ~: for '
              'regex, or a leading - to exclude — e.g. -package:test or '
              'tag~:auth.*. Quote values with spaces.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ActionChip(
              label: const Text('package:'),
              onPressed: () =>
                  onAppendToken('package:', applyImmediately: false),
            ),
            ActionChip(
              label: Text(isIos ? 'category:' : 'tag:'),
              onPressed: () => onAppendToken(
                isIos ? 'category:' : 'tag:',
                applyImmediately: false,
              ),
            ),
            ActionChip(
              label: const Text('message:'),
              onPressed: () =>
                  onAppendToken('message:', applyImmediately: false),
            ),
            ActionChip(
              label: const Text('level:error'),
              onPressed: () =>
                  onAppendToken('level:error', applyImmediately: true),
            ),
            ActionChip(
              label: const Text('age:1h'),
              onPressed: () => onAppendToken('age:1h', applyImmediately: true),
            ),
            ActionChip(
              label: const Text('-package:'),
              onPressed: () =>
                  onAppendToken('-package:', applyImmediately: false),
            ),
            ActionChip(
              label: const Text('message~:'),
              onPressed: () =>
                  onAppendToken('message~:', applyImmediately: false),
            ),
          ],
        ),
      ),
    );
  }
}
