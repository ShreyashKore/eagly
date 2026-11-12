import 'package:flutter/material.dart';

import '../../../presentation/components/feature_view.dart';
import '../../../presentation/components/overflow_toolbar.dart';
import '../data/file_view_options.dart';
import '../file_manager_controller.dart';

/// Header of the file-manager pane: back / up before the title, refresh as
/// its primary control, then the view toggle and the file actions (new
/// folder, upload, download/delete for the current selection). Action
/// callbacks are owned by the feature view because they need dialogs /
/// snackbars. The standard [FeatureViewHeader] does the rest — grip, drag
/// area, overflow, close.
class const FileManagerToolbar({
  super.key,
  required final FileManagerController controller,
  required final VoidCallback onUpload,
  required final VoidCallback onNewFolder,
  required final VoidCallback onDownloadSelected,
  required final VoidCallback onDeleteSelected,
  required final VoidCallback? onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = controller.isBusy;
    final hasSelection = controller.selectedEntry != null;
    final isList = controller.viewMode == FileManagerViewMode.list;

    return FeatureViewHeader(
      title: 'Files',
      closeTooltip: 'Close files pane',
      onClose: onClose,
      leading: [
        ToolbarAction(
          icon: Icons.arrow_back,
          label: 'Back',
          onPressed: controller.canGoBack && !busy
              ? controller.navigateBack
              : null,
        ),
        ToolbarAction(
          icon: Icons.arrow_upward,
          label: 'Up one level',
          onPressed: controller.canGoUp && !busy ? controller.navigateUp : null,
        ),
      ],
      primary: [
        ToolbarAction(
          icon: Icons.refresh,
          label: 'Refresh',
          busy: controller.isLoading,
          onPressed: busy ? null : controller.refresh,
        ),
      ],
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
    );
  }
}
