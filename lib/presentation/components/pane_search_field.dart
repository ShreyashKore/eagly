import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// The strip under a pane's header that holds its search box (and, in Apps,
/// the view options): the header's surface with a divider below.
class const PaneSearchBar({super.key, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: child,
    );
  }
}

/// A pane's search box: a search icon, [hint], and while there is text a
/// clear button, which Esc also presses. Clearing reports `''` through
/// [onChanged], the same as deleting the text by hand.
class const PaneSearchField({
  super.key,
  required final TextEditingController controller,
  required final ValueChanged<String> onChanged,
  required final String hint,

  /// While set (and there is text), a small spinner with this tooltip sits
  /// before the clear button — a search still running in the background.
  final String? busyMessage,

  /// A shorter field with smaller icons, for a narrow side panel.
  final bool compact = false,
}) extends StatelessWidget {
  void _clear() {
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: context.scaled(compact ? 30 : 34),
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          return CallbackShortcuts(
            bindings: {
              if (hasText)
                const SingleActivator(LogicalKeyboardKey.escape): _clear,
            },
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                prefixIcon: Icon(Icons.search, size: compact ? 16 : 18),
                suffixIcon: !hasText
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busyMessage != null)
                            Tooltip(
                              message: busyMessage!,
                              child: SizedBox.square(
                                dimension: context.scaled(12),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                          AppIconButton(
                            tooltip: 'Clear search',
                            iconSize: compact ? 14 : 15,
                            padding: 4,
                            onPressed: _clear,
                            icon: Icons.close,
                          ),
                        ],
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          );
        },
      ),
    );
  }
}
