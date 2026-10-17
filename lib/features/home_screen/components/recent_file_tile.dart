import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../utils/utils.dart';

class const RecentFileTile({
  super.key,
  required final String path,
  required final VoidCallback onOpen,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extractFileName(path),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Gap(8),
              AppIconButton(
                tooltip: 'Remove from recent',
                iconSize: 16,
                onPressed: onRemove,
                icon: Icons.close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
