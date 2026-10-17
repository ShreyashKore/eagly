import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Leading content for the synthetic "Imported Logs" workspace tab: a file
/// icon and label instead of a device's connection dot + platform label.
class const WorkspaceLabel({super.key, required this.theme})
    extends StatelessWidget {
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.description_outlined,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const Gap(6),
        Flexible(
          child: Text(
            'Imported Logs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
