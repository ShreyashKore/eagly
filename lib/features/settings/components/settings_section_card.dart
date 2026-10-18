import 'package:flutter/material.dart';

/// Titled card wrapping one settings section's rows, separated by dividers.
///
/// The card adds no padding of its own: each row brings it, so a tappable
/// row's hover and splash fill the card edge to edge instead of stopping at
/// an inset box. List tiles get [rowPadding] through the [ListTileTheme] —
/// leave their `contentPadding` unset — and any other row wraps itself in a
/// [SettingsRow].
class const SettingsSectionCard({
  super.key,
  required final String title,
  required final List<Widget> children,
}) extends StatelessWidget {
  /// Padding around every row's content, tile or not.
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        Card(
          elevation: 0,
          // Keeps the first and last rows' ink inside the rounded corners.
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: theme.colorScheme.surfaceContainerLow,
          child: ListTileTheme.merge(
            contentPadding: rowPadding,
            child: Column(
              children: List<Widget>.generate(children.length * 2 - 1, (i) {
                if (i.isEven) return children[i ~/ 2];
                return Divider(
                  height: 1,
                  indent: rowPadding.left,
                  endIndent: rowPadding.right,
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

/// A settings row that isn't a list tile — a label with a custom control —
/// padded to line up with the tiles around it.
class const SettingsRow({super.key, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Padding(padding: SettingsSectionCard.rowPadding, child: child);
}
