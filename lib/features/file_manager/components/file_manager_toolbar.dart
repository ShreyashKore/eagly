import 'package:flutter/material.dart';

import '../file_manager_controller.dart';

/// Top toolbar of the file-manager pane: navigation (back / up / refresh),
/// view-mode toggle, and the file actions (new folder, upload, download/delete
/// for the current selection). Action callbacks are owned by the feature view
/// because they need dialogs / snackbars.
class FileManagerToolbar extends StatelessWidget {
  const FileManagerToolbar({
    super.key,
    required this.controller,
    required this.onUpload,
    required this.onNewFolder,
    required this.onDownloadSelected,
    required this.onDeleteSelected,
    required this.onClose,
  });

  final FileManagerController controller;
  final VoidCallback onUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onDownloadSelected;
  final VoidCallback onDeleteSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = controller.isBusy;
    final hasSelection = controller.selectedEntry != null;
    final isList = controller.viewMode == FileManagerViewMode.list;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            iconSize: 20,
            onPressed: controller.canGoBack && !busy
                ? controller.navigateBack
                : null,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: 'Up one level',
            iconSize: 20,
            onPressed: controller.canGoUp && !busy
                ? controller.navigateUp
                : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Refresh',
            iconSize: 20,
            onPressed: busy ? null : controller.refresh,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const Spacer(),
          IconButton(
            tooltip: isList ? 'Grid view' : 'List view',
            iconSize: 20,
            onPressed: controller.toggleViewMode,
            icon: Icon(
              isList ? Icons.grid_view_rounded : Icons.view_list_rounded,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 24,
            child: VerticalDivider(
              width: 2,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(width: 4),
          if (controller.supportsCreateDirectory)
            IconButton(
              tooltip: 'New folder',
              iconSize: 20,
              onPressed: busy ? null : onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          IconButton(
            tooltip: 'Upload to ${controller.currentPath}',
            iconSize: 20,
            onPressed: busy ? null : onUpload,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: hasSelection
                ? 'Download ${controller.selectedEntry!.name}'
                : 'Select an item to download',
            iconSize: 20,
            onPressed: hasSelection && !busy ? onDownloadSelected : null,
            icon: const Icon(Icons.download_outlined),
          ),
          if (controller.supportsDelete)
            IconButton(
              tooltip: hasSelection
                  ? 'Delete ${controller.selectedEntry!.name}'
                  : 'Select an item to delete',
              iconSize: 20,
              color: hasSelection ? theme.colorScheme.error : null,
              onPressed: hasSelection && !busy ? onDeleteSelected : null,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Close files pane',
            iconSize: 20,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
