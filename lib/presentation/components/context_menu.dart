import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An icon and a label, the row of a context-menu entry. [color] tints both
/// (a destructive entry); [shortcut] is a key hint on the right.
class const MenuRow(
  final IconData icon,
  final String label, {
  super.key,
  final Color? color,
  final String? shortcut,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
        if (shortcut != null) ...[
          const SizedBox(width: 24),
          Text(
            shortcut!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.eaglyTheme.tertiaryTextColor),
          ),
        ],
      ],
    );
  }
}

/// A global pointer position as a [showMenu] anchor.
RelativeRect menuPositionAt(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);
