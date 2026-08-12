import 'package:flutter/material.dart';

/// Titled card wrapping one settings section's rows, separated by dividers.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: List<Widget>.generate(children.length * 2 - 1, (i) {
                final index = i ~/ 2;
                if (i.isEven) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: children[index],
                  );
                }
                return const Divider(height: 1);
              }),
            ),
          ),
        ),
      ],
    );
  }
}
