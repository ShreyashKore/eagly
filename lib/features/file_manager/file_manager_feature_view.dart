import 'package:flutter/material.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/drop_zone.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/install_conflict_dialog.dart';
import '../../presentation/theme/app_theme.dart';
import '../../services/app_install_service.dart';
import '../../utils/utils.dart';
import 'components/file_breadcrumb_bar.dart';
import 'components/file_context_menu.dart';
import 'components/file_grid_view.dart';
import 'components/file_list_view.dart';
import 'components/file_manager_toolbar.dart';
import 'data/device_file_entry.dart';
import 'file_manager_controller.dart';

/// File-manager feature pane. Composes the toolbar, breadcrumb, the active
/// list/grid view (with empty/error/loading states), a busy overlay for
/// transfers, and a status bar. Owns the dialogs and snackbars for the file
/// actions. Files dropped onto the pane are copied into the folder it shows —
/// an app for this device first asks whether to install it instead. [onClose]
/// hides the pane (handled by the device screen).
class const FileManagerFeatureView({
  super.key,
  required final FileManagerController controller,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

  @override
  State<FileManagerFeatureView> createState() => _FileManagerFeatureViewState();
}

class _FileManagerFeatureViewState
    extends FeatureViewState<FileManagerFeatureView> {
  FileManagerController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  void _showSnackBar(String? message) {
    if (message == null) return;
    showSnackBar(message);
  }

  late final FileManagerActions _actions = FileManagerActions(
    onDownload: _handleDownload,
    onRename: _handleRename,
    onDelete: _handleDelete,
    onUpload: _handleUpload,
    onNewFolder: _handleNewFolder,
  );

  Future<void> _handleUpload() async {
    _showSnackBar(await controller.uploadFiles());
  }

  Future<void> _handleDownload([DeviceFileEntry? entry]) async {
    final target = entry ?? controller.selectedEntry;
    if (target == null) return;
    _showSnackBar(await controller.downloadEntry(target));
  }

  Future<void> _handleNewFolder() async {
    final name = await _promptForName(
      title: 'New folder',
      label: 'Folder name',
      hint: 'Untitled folder',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    _showSnackBar(await controller.createDirectory(name));
  }

  Future<void> _handleRename(DeviceFileEntry entry) async {
    final name = await _promptForName(
      title: 'Rename ${entry.name}',
      label: 'New name',
      initialValue: entry.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == entry.name) return;
    _showSnackBar(await controller.renameEntry(entry, name));
  }

  Future<void> _handleDelete([DeviceFileEntry? entry]) async {
    final target = entry ?? controller.selectedEntry;
    if (target == null) return;
    final confirmed = await _confirmDelete(target);
    if (!confirmed) return;
    _showSnackBar(await controller.deleteEntry(target));
  }

  Future<void> _handleDrop(List<String> paths) async {
    final session = controller.session;
    final installables = paths
        .where(
          (path) =>
              AppInstallService.inferSupportedPlatform(path) ==
              session.platform,
        )
        .toList(growable: false);
    // Disconnected: nothing to ask — the drop reports it can't reach the device.
    var installApps = false;
    if (installables.isNotEmpty && controller.isConnected) {
      final install = await _askInstallOrCopy(
        installables,
        otherCount: paths.length - installables.length,
      );
      if (install == null || !mounted) return;
      installApps = install;
    }
    final result = await session.handleDroppedPaths(
      paths,
      copyDirectory: controller.currentPath,
      installApps: installApps,
    );
    if (!mounted || result == null) return;
    _showSnackBar(result.message);
    for (final conflict in result.conflicts) {
      if (!mounted) return;
      await presentAppInstallResult(
        context,
        session: session,
        result: conflict,
        showMessage: _showSnackBar,
      );
    }
  }

  /// Asks whether dropped [installables] should be installed or copied into
  /// the current folder; [otherCount] non-app files are copied either way.
  /// Returns true to install, false to copy, or null when cancelled.
  Future<bool?> _askInstallOrCopy(
    List<String> installables, {
    required int otherCount,
  }) {
    final device = controller.device.displayName;
    final folder = controller.currentPath;
    final subject = installables.length == 1
        ? extractFileName(installables.single)
        : '${installables.length} apps';
    final pronoun = installables.length == 1 ? 'it' : 'them';
    final others = switch (otherCount) {
      0 => '',
      1 => '\n\nThe other file is copied to $folder either way.',
      _ => '\n\nThe other $otherCount files are copied to $folder either way.',
    };
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Install $subject?'),
        content: Text(
          'Install $pronoun on $device, or copy $pronoun to $folder?$others',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Copy'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForName({
    required String title,
    required String label,
    required String confirmLabel,
    String? hint,
    String? initialValue,
  }) async {
    final fieldController = TextEditingController(text: initialValue);
    if (initialValue != null) {
      fieldController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialValue.length,
      );
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: fieldController,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
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
            child: Text(confirmLabel),
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
  Widget buildContent(BuildContext context) {
    return DropZone(
      onDrop: _handleDrop,
      builder: (context, isHovered) => Stack(
        children: [
          Positioned.fill(child: _buildPane()),
          if (isHovered) Positioned.fill(child: _buildDropHighlight(context)),
        ],
      ),
    );
  }

  Widget _buildPane() {
    return FeaturePane(
      header: Column(
        mainAxisSize: MainAxisSize.min,
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
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(context)),
          if (controller.isBusy) _buildBusyOverlay(context),
        ],
      ),
      statusBar: _buildStatusBar(context),
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
    final viewer = switch (controller.viewMode) {
      FileManagerViewMode.list => FileListView(
        controller: controller,
        actions: _actions,
      ),
      FileManagerViewMode.grid => FileGridView(
        controller: controller,
        actions: _actions,
      ),
    };

    // Right-click on empty space (rows handle their own secondary tap and, being
    // deeper, win the gesture arena) opens the current-directory menu.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) => showFileAreaMenu(
        context,
        details.globalPosition,
        controller: controller,
        actions: _actions,
      ),
      child: viewer,
    );
  }

  /// Outlines the pane while files are dragged over it, naming the folder
  /// they will land in.
  Widget _buildDropHighlight(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  'Copy to ${controller.currentPath}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final style = theme.textTheme.bodySmall?.copyWith(
      color: context.eaglyTheme.tertiaryTextColor,
    );
    return FeatureStatusBar(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        Text(
          '${controller.directoryCount} folders · ${controller.fileCount} files',
          style: style,
        ),
        const Spacer(),
        if (selected != null)
          Flexible(
            child: Text(
              selected.name,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ],
    );
  }
}
