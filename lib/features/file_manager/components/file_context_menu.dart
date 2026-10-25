import 'package:flutter/material.dart';

import '../data/device_file_entry.dart';
import '../file_manager_controller.dart';
import '../../../presentation/components/context_menu.dart';
import '../../../presentation/components/snack_bars.dart';

/// The file actions that need dialogs / pickers / snackbars. These are owned by
/// the feature view and invoked from both the toolbar and the context menus, so
/// the menu helpers stay free of dialog logic.
class const FileManagerActions({
  required final void Function(DeviceFileEntry entry) onDownload,
  required final void Function(DeviceFileEntry entry) onRename,
  required final void Function(DeviceFileEntry entry) onDelete,
  required final VoidCallback onUpload,
  required final VoidCallback onNewFolder,
});

enum _EntryAction { open, download, rename, copyPath, copyName, delete }

enum _AreaAction { upload, newFolder, refresh }

/// Right-click menu for a single [entry], with options appropriate to its kind
/// (folders/symlinks get "Open"). [position] is the global pointer location.
Future<void> showFileEntryMenu(
  BuildContext context,
  Offset position, {
  required FileManagerController controller,
  required DeviceFileEntry entry,
  required FileManagerActions actions,
}) async {
  final theme = Theme.of(context);
  final result = await showMenu<_EntryAction>(
    context: context,
    position: menuPositionAt(position),
    items: [
      if (entry.isNavigable)
        const PopupMenuItem(
          value: _EntryAction.open,
          child: MenuRow(Icons.folder_open_outlined, 'Open'),
        ),
      const PopupMenuItem(
        value: _EntryAction.download,
        child: MenuRow(Icons.download_outlined, 'Download…'),
      ),
      if (controller.supportsRename)
        const PopupMenuItem(
          value: _EntryAction.rename,
          child: MenuRow(Icons.drive_file_rename_outline, 'Rename…'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: _EntryAction.copyPath,
        child: MenuRow(Icons.link_outlined, 'Copy path'),
      ),
      const PopupMenuItem(
        value: _EntryAction.copyName,
        child: MenuRow(Icons.title_outlined, 'Copy name'),
      ),
      if (controller.supportsDelete) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _EntryAction.delete,
          child: MenuRow(
            Icons.delete_outline,
            'Delete',
            color: theme.colorScheme.error,
          ),
        ),
      ],
    ],
  );

  if (result == null || !context.mounted) return;
  switch (result) {
    case _EntryAction.open:
      controller.open(entry);
    case _EntryAction.download:
      actions.onDownload(entry);
    case _EntryAction.rename:
      actions.onRename(entry);
    case _EntryAction.copyPath:
      await copyWithToast(context, entry.path, 'Copied path.');
    case _EntryAction.copyName:
      await copyWithToast(context, entry.name, 'Copied name.');
    case _EntryAction.delete:
      actions.onDelete(entry);
  }
}

/// Right-click menu for empty space in the listing: actions that apply to the
/// current directory itself.
Future<void> showFileAreaMenu(
  BuildContext context,
  Offset position, {
  required FileManagerController controller,
  required FileManagerActions actions,
}) async {
  final result = await showMenu<_AreaAction>(
    context: context,
    position: menuPositionAt(position),
    items: [
      const PopupMenuItem(
        value: _AreaAction.upload,
        child: MenuRow(Icons.upload_file_outlined, 'Upload here…'),
      ),
      if (controller.supportsCreateDirectory)
        const PopupMenuItem(
          value: _AreaAction.newFolder,
          child: MenuRow(Icons.create_new_folder_outlined, 'New folder…'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: _AreaAction.refresh,
        child: MenuRow(Icons.refresh, 'Refresh'),
      ),
    ],
  );

  if (result == null) return;
  switch (result) {
    case _AreaAction.upload:
      actions.onUpload();
    case _AreaAction.newFolder:
      actions.onNewFolder();
    case _AreaAction.refresh:
      controller.refresh();
  }
}
