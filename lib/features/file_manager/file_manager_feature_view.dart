import 'package:flutter/material.dart';

import '../../ui/components/centered_state_message.dart';
import 'components/file_breadcrumb_bar.dart';
import 'components/file_grid_view.dart';
import 'components/file_list_view.dart';
import 'components/file_manager_toolbar.dart';
import 'data/device_file_entry.dart';
import 'file_manager_controller.dart';

/// File-manager feature pane. Composes the toolbar, breadcrumb, the active
/// list/grid view (with empty/error/loading states), a busy overlay for
/// transfers, and a status bar. Owns the dialogs and snackbars for the file
/// actions. [onClose] hides the pane (handled by the device screen).
class FileManagerFeatureView extends StatefulWidget {
  const FileManagerFeatureView({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final FileManagerController controller;
  final VoidCallback onClose;

  @override
  State<FileManagerFeatureView> createState() => _FileManagerFeatureViewState();
}

class _FileManagerFeatureViewState extends State<FileManagerFeatureView> {
  FileManagerController get controller => widget.controller;

  void _showSnackBar(String? message) {
    if (message == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleUpload() async {
    _showSnackBar(await controller.uploadFiles());
  }

  Future<void> _handleDownload() async {
    final selected = controller.selectedEntry;
    if (selected == null) return;
    _showSnackBar(await controller.downloadEntry(selected));
  }

  Future<void> _handleNewFolder() async {
    final name = await _promptForName();
    if (name == null) return;
    _showSnackBar(await controller.createDirectory(name));
  }

  Future<void> _handleDelete() async {
    final selected = controller.selectedEntry;
    if (selected == null) return;
    final confirmed = await _confirmDelete(selected);
    if (!confirmed) return;
    _showSnackBar(await controller.deleteEntry(selected));
  }

  Future<String?> _promptForName() async {
    final fieldController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: fieldController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'Untitled folder',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(fieldController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    fieldController.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<bool> _confirmDelete(DeviceFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(
          entry.isDirectory
              ? 'This permanently removes the folder and all its contents from the device.'
              : 'This permanently removes the file from the device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FileManagerToolbar(
                controller: controller,
                onUpload: _handleUpload,
                onNewFolder: _handleNewFolder,
                onDownloadSelected: _handleDownload,
                onDeleteSelected: _handleDelete,
                onClose: widget.onClose,
              ),
              FileBreadcrumbBar(controller: controller),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildBody(context)),
                    if (controller.isBusy) _buildBusyOverlay(context),
                  ],
                ),
              ),
              _buildStatusBar(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (controller.loadState) {
      case FileLoadState.idle:
        return const SizedBox.shrink();
      case FileLoadState.loading:
        if (controller.entryCount == 0) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildViewer();
      case FileLoadState.error:
        return CenteredStateMessage(
          icon: Icons.folder_off_outlined,
          title: 'Could not open this folder',
          description: controller.error ?? 'Something went wrong.',
          footer: FilledButton.icon(
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        );
      case FileLoadState.ready:
        if (controller.entryCount == 0) {
          return const CenteredStateMessage(
            icon: Icons.folder_open_outlined,
            title: 'Empty folder',
            description: 'There are no files or folders here.',
          );
        }
        return _buildViewer();
    }
  }

  Widget _buildViewer() {
    return switch (controller.viewMode) {
      FileManagerViewMode.list => FileListView(controller: controller),
      FileManagerViewMode.grid => FileGridView(controller: controller),
    };
  }

  Widget _buildBusyOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        child: Center(
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    controller.busyLabel ?? 'Working…',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedEntry;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(
            '${controller.directoryCount} folders · ${controller.fileCount} files',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (selected != null)
            Flexible(
              child: Text(
                selected.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
