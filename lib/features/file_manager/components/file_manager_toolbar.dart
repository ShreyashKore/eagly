import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/overflow_toolbar.dart';
import '../../../presentation/components/workspace_pane_scope.dart';
import '../file_manager_controller.dart';
import '../../../presentation/theme/app_theme.dart';

/// Top toolbar of the file-manager pane: navigation (back / up / refresh),
/// view-mode toggle, and the file actions (new folder, upload, download/delete
/// for the current selection). Action callbacks are owned by the feature view
/// because they need dialogs / snackbars.
///
/// Navigation and the close button are always visible; the actions in between
/// collapse into an overflow menu (last one first) when the pane is narrow.
/// In the device workspace a [PaneGrip] leads the bar and the empty stretch
/// after navigation drags the pane like a title bar; while the pane sits in
/// a tab group its chip is the handle and has the close button, so the bar
/// shows neither.
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
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = controller.isBusy;
    final hasSelection = controller.selectedEntry != null;
    final isList = controller.viewMode == FileManagerViewMode.list;

    return Container(
      height: context.scaled(48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: OverflowToolbar(
        spacing: 0,
        leading: [
          const PaneGrip(),
          AppIconButton(
            tooltip: 'Back',
            iconSize: 20,
            onPressed: controller.canGoBack && !busy
                ? controller.navigateBack
                : null,
            icon: Icons.arrow_back,
          ),
          AppIconButton(
            tooltip: 'Up one level',
            iconSize: 20,
            onPressed: controller.canGoUp && !busy
                ? controller.navigateUp
                : null,
            icon: Icons.arrow_upward,
          ),
          AppIconButton(
            tooltip: 'Refresh',
            iconSize: 20,
            busy: controller.isLoading,
            onPressed: busy ? null : controller.refresh,
            icon: Icons.refresh,
          ),
        ],
        flexible: const PaneDragArea(child: SizedBox.expand()),
        actions: [
          ToolbarAction(
            icon: isList ? Icons.grid_view_rounded : Icons.view_list_rounded,
            label: isList ? 'Grid view' : 'List view',
            onPressed: controller.toggleViewMode,
          ),
          if (controller.supportsCreateDirectory)
            ToolbarAction(
              icon: Icons.create_new_folder_outlined,
              label: 'New folder',
              dividerBefore: true,
              onPressed: busy ? null : onNewFolder,
            ),
          ToolbarAction(
            icon: Icons.upload_file_outlined,
            label: 'Upload',
            tooltip: 'Upload to ${controller.currentPath}',
            dividerBefore: !controller.supportsCreateDirectory,
            onPressed: busy ? null : onUpload,
          ),
          ToolbarAction(
            icon: Icons.download_outlined,
            label: 'Download',
            tooltip: hasSelection
                ? 'Download ${controller.selectedEntry!.name}'
                : 'Select an item to download',
            onPressed: hasSelection && !busy ? onDownloadSelected : null,
          ),
          if (controller.supportsDelete)
            ToolbarAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              tooltip: hasSelection
                  ? 'Delete ${controller.selectedEntry!.name}'
                  : 'Select an item to delete',
              color: hasSelection ? theme.colorScheme.error : null,
              onPressed: hasSelection && !busy ? onDeleteSelected : null,
            ),
        ],
        trailing: [
          if (WorkspacePaneScope.showsOwnClose(context))
            AppIconButton(
              tooltip: 'Close files pane',
              iconSize: 20,
              onPressed: onClose,
              icon: Icons.close,
            ),
        ],
      ),
    );
  }
}
