import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/hover_builder.dart';
import '../../../presentation/theme/platform_look.dart';

/// One entry of the home page's Start list: what it does, and the key that
/// does it from anywhere on the home page (see [HomeStartShortcuts]).
class const HomeStartAction({
  required final IconData icon,
  required final String label,
  required final LogicalKeyboardKey key,
  required final VoidCallback onPressed,
});

/// Binds each [HomeStartAction]'s key — ⌘ on macOS, Ctrl elsewhere — while
/// focus is inside [child]. Takes focus on mount, so the keys work as soon
/// as the home page shows.
class const HomeStartShortcuts({
  super.key,
  required final List<HomeStartAction> actions,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        for (final action in actions)
          SingleActivator(action.key, meta: mac, control: !mac):
              action.onPressed,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// The home page's Start list: a column of quiet rows, each with its icon,
/// its label and its shortcut, in the manner of a desktop IDE's start page.
class const HomeStartList({
  super.key,
  required final List<HomeStartAction> actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionLabel('Start'),
        for (final action in actions) _StartRow(action: action),
      ],
    );
  }
}

/// A small muted heading over a group on the home page.
class const HomeSectionLabel(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class const _StartRow({required final HomeStartAction action})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(PlatformLook.controlRadius);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => Material(
        color: hovered
            ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: action.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(action.icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    action.label,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ShortcutHint(logicalKey: action.key),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The platform's spelling of ⌘/Ctrl + [logicalKey], in a key-cap outline.
class const ShortcutHint({
  super.key,
  required final LogicalKeyboardKey logicalKey,
}) extends StatelessWidget {
  /// `⌘O` on macOS, `Ctrl+O` elsewhere.
  static String label(LogicalKeyboardKey key) {
    final letter = key.keyLabel.toUpperCase();
    return defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘$letter'
        : 'Ctrl+$letter';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label(logicalKey),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
