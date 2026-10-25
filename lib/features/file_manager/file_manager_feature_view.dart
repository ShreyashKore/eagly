import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/drop_zone.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/install_conflict_dialog.dart';
import '../../presentation/components/min_width_box.dart';
import '../../presentation/theme/app_theme.dart';
import '../../services/app_install_service.dart';
import '../../utils/utils.dart';
import 'components/file_breadcrumb_bar.dart';
import 'components/file_context_menu.dart';
import 'components/file_entry_visuals.dart';
import 'components/file_filter_field.dart';
import 'components/file_grid_view.dart';
import 'components/file_list_view.dart';
import 'components/file_manager_toolbar.dart';
import 'components/file_view_menu.dart';
import 'data/device_file_entry.dart';
import 'data/file_view_options.dart';
import 'file_manager_controller.dart';
import '../../presentation/components/busy_overlay.dart';
import '../../presentation/components/confirm_dialog.dart';

/// File-manager feature pane. Composes the toolbar, breadcrumb, the active
/// list/grid view (with empty/error/loading states), a busy overlay for
/// transfers, and a status bar. Owns the dialogs and snackbars for the file
/// actions, and the focus of the filter and the listing (⌘F / Ctrl+F jumps
/// to the filter). Files dropped onto the pane are copied into the folder it shows —
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

  final FocusNode _filterFocus = FocusNode(debugLabel: 'files filter');
  final FocusNode _listFocus = FocusNode(debugLabel: 'files listing');

  @override
  void dispose() {
    _filterFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _focusFilter() {
    _filterFocus.requestFocus();
    // Select what's there, so typing replaces the old filter.
    final field = _filterFocus.context
        ?.findAncestorStateOfType<EditableTextState>();
    field?.selectAll(SelectionChangedCause.keyboard);
  }

  late final FileManagerActions _actions = FileManagerActions(
    onDownload: _handleDownload,
    onRename: _handleRename,
    onDelete: _handleDelete,
    onUpload: _handleUpload,
    onNewFolder: _handleNewFolder,
  );

  Future<void> _handleUpload() async {
    showSnackBar(await controller.uploadFiles());
  }

  Future<void> _handleDownload([DeviceFileEntry? entry]) async {
    final target = entry ?? controller.selectedEntry;
    if (target == null) return;
    showSnackBar(await controller.downloadEntry(target));
  }

  Future<void> _handleNewFolder() async {
    final name = await _promptForName(
      title: 'New folder',
      label: 'Folder name',
      hint: 'Untitled folder',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    showSnackBar(await controller.createDirectory(name));
  }

  Future<void> _handleRename(DeviceFileEntry entry) async {
    final name = await _promptForName(
      title: 'Rename ${entry.name}',
      label: 'New name',
      initialValue: entry.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == entry.name) return;
    showSnackBar(await controller.renameEntry(entry, name));
  }

  Future<void> _handleDelete([DeviceFileEntry? entry]) async {
    final target = entry ?? controller.selectedEntry;
    if (target == null) return;
    final confirmed = await _confirmDelete(target);
    if (!confirmed) return;
    showSnackBar(await controller.deleteEntry(target));
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
    showSnackBar(result.message);
    for (final conflict in result.conflicts) {
      if (!mounted) return;
      await presentAppInstallResult(
        context,
        session: session,
        result: conflict,
        showMessage: showSnackBar,
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

  Future<bool> _confirmDelete(DeviceFileEntry entry) => showConfirmDialog(
    context,
    title: 'Delete ${entry.name}?',
    message: entry.isDirectory
        ? 'This permanently removes the folder and all its contents from the device.'
        : 'This permanently removes the file from the device.',
    confirmLabel: 'Delete',
    destructive: true,
  );

  @override
  Widget buildContent(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusFilter,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusFilter,
      },
      child: DropZone(
        onDrop: _handleDrop,
        builder: (context, isHovered) => Stack(
          children: [
            Positioned.fill(child: _buildPane()),
            if (isHovered) Positioned.fill(child: _buildDropHighlight(context)),
          ],
        ),
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
          LayoutBuilder(
            builder: (context, constraints) => MinWidthBox(
              minWidth: 200,
              child: FileBreadcrumbBar(
                controller: controller,
                trailing: [
                  const SizedBox(width: 8),
                  FileFilterField(
                    controller: controller,
                    focusNode: _filterFocus,
                    listFocusNode: _listFocus,
                    width: (constraints.maxWidth * 0.35).clamp(90, 220),
                  ),
                  FileViewMenuButton(controller: controller),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(context)),
          if (controller.isBusy) BusyOverlay(label: controller.busyLabel),
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
          footer: RetryButton(onPressed: controller.refresh),
        );
      case FileLoadState.ready:
        if (controller.entryCount == 0) {
          return const CenteredStateMessage(
            icon: Icons.folder_open_outlined,
            title: 'Empty folder',
            description: 'There are no files or folders here.',
          );
        }
        if (controller.visibleCount == 0) return _buildNothingShown();
        return _buildViewer();
    }
  }

  /// Everything here is filtered out or hidden: say which, with the way back.
  Widget _buildNothingShown() {
    if (controller.isFiltered) {
      return CenteredStateMessage(
        icon: Icons.search_off,
        title: 'No matches',
        description:
            'Nothing in this folder matches "${controller.filterText.trim()}".',
        footer: OutlinedButton(
          onPressed: () => controller.setFilterText(''),
          child: const Text('Clear filter'),
        ),
      );
    }
    return CenteredStateMessage(
      icon: Icons.visibility_off_outlined,
      title: 'Only hidden files',
      description: 'This folder has only hidden files.',
      footer: OutlinedButton(
        onPressed: () => controller.setShowHidden(true),
        child: const Text('Show hidden files'),
      ),
    );
  }

  Widget _buildViewer() {
    final viewer = switch (controller.viewMode) {
      FileManagerViewMode.list => FileListView(
        controller: controller,
        actions: _actions,
        focusNode: _listFocus,
      ),
      FileManagerViewMode.grid => FileGridView(
        controller: controller,
        actions: _actions,
        focusNode: _listFocus,
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

  /// "12 folders · 30 files", or "5 of 42 items" while filtered, noting
  /// any hidden files left out.
  String _countsLabel() {
    final hidden = controller.hiddenCount;
    final parts = [
      if (controller.isFiltered)
        '${controller.visibleCount} of ${controller.entryCount - hidden} items'
      else
        '${pluralize(controller.directoryCount, 'folder')} · '
            '${pluralize(controller.fileCount, 'file')}',
      if (hidden > 0) '$hidden hidden',
    ];
    return parts.join(' · ');
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
        Text(_countsLabel(), style: style),
        const Spacer(),
        if (selected != null)
          Flexible(
            child: Text(
              selected.isFile
                  ? '${selected.name} · ${FileEntryVisuals.formatSize(selected)}'
                  : selected.name,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ],
    );
  }
}
