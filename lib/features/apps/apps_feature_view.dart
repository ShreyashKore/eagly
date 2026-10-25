import 'package:eagly/presentation/components/feature_view.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../data/device.dart';
import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/overflow_toolbar.dart';
import 'apps_controller.dart';
import 'components/app_context_menu.dart';
import 'components/app_list_row.dart';
import 'components/app_tile.dart';
import 'data/app_info.dart';
import 'data/apps_view_options.dart';
import '../../presentation/theme/app_theme.dart';
import '../../presentation/components/snack_bars.dart';
import '../../presentation/components/busy_overlay.dart';
import '../../presentation/components/pane_search_field.dart';
import '../../presentation/components/confirm_dialog.dart';

/// Apps feature pane: lists installed apps as an icon grid or a detailed list
/// (with a resizable icon), pins the most recently installed apps above them,
/// offers search and (Android) a system-apps toggle, and drives the per-app
/// context menu actions. Owns the confirmation dialogs and snackbars for destructive
/// actions. [onClose] hides the pane (handled by the device screen).
class const AppsFeatureView({
  super.key,
  required final AppsController controller,
  required super.onClose,
}) extends FeatureView {
  @override
  State<AppsFeatureView> createState() => _AppsFeatureViewState();
}

class _AppsFeatureViewState extends State<AppsFeatureView> {
  AppsController get controller => widget.controller;

  /// Seeded from the controller: the pane is rebuilt from scratch each time
  /// it is reopened, but the controller (and so the active filter) outlives
  /// it — an empty field over a filtered list would hide why apps are missing.
  late final TextEditingController _searchController = TextEditingController(
    text: controller.searchText,
  );

  @override
  void didUpdateWidget(covariant AppsFeatureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, controller) &&
        _searchController.text != controller.searchText) {
      _searchController.text = controller.searchText;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String? message) {
    if (message != null && mounted) showMessageSnackBar(context, message);
  }

  Future<void> _handleLaunch(AppInfo app) async {
    _showSnackBar(await controller.launch(app));
  }

  Future<void> _handleForceStop(AppInfo app) async {
    _showSnackBar(await controller.forceStop(app));
  }

  Future<void> _handleAppInfo(AppInfo app) async {
    await controller.openAppInfo(app);
  }

  void _handleViewLogs(AppInfo app) {
    controller.viewLogs(app);
  }

  Future<void> _handleClearData(AppInfo app) async {
    if (_blockSystemApp(app)) return;
    if (!controller.canClearDataOf(app)) {
      _showSnackBar(
        "${app.displayName} isn't a debug build — iOS keeps its data sealed.",
      );
      return;
    }
    final confirmed = await _confirmDestructive(
      title: 'Clear data for ${app.displayName}?',
      message: controller.device is IosDevice
          ? "This permanently deletes the app's documents, caches and "
                'settings on the device. Its keychain items stay.'
          : "This permanently deletes the app's data and cache on the "
                'device. It will restart as if freshly installed.',
      confirmLabel: 'Clear Data',
    );
    if (!confirmed) return;
    _showSnackBar(await controller.clearData(app));
  }

  Future<void> _handleUninstall(AppInfo app) async {
    if (_blockSystemApp(app)) return;
    final confirmed = await _confirmDestructive(
      title: 'Uninstall ${app.displayName}?',
      message: 'This permanently removes the app and its data from the device.',
      confirmLabel: 'Uninstall',
    );
    if (!confirmed) return;
    _showSnackBar(await controller.uninstall(app));
  }

  /// Last line of defence for the irreversible actions: the context menu
  /// already disables them for a system app, so reaching here means something
  /// else routed one in. Refuse instead of trusting the caller.
  bool _blockSystemApp(AppInfo app) {
    if (!app.isSystemApp) return false;
    _showSnackBar(
      '${app.displayName} is a system app — that action is not available '
      'for preinstalled packages.',
    );
    return true;
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmLabel,
  }) => showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: true,
  );

  late final AppActions _actions = AppActions(
    onLaunch: _handleLaunch,
    onForceStop: _handleForceStop,
    onClearData: _handleClearData,
    onAppInfo: _handleAppInfo,
    onViewLogs: _handleViewLogs,
    onUninstall: _handleUninstall,
  );

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
              _Header(controller: controller, onClose: widget.onClose!),
              _Toolbar(
                controller: controller,
                searchController: _searchController,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildBody(context)),
                    if (controller.isBusy)
                      BusyOverlay(label: controller.busyLabel),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (controller.loadState) {
      case AppLoadState.idle:
      case AppLoadState.loading:
        if (controller.apps.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildApps(context);
      case AppLoadState.error:
        return CenteredStateMessage(
          icon: Icons.apps_outlined,
          title: 'Could not load apps',
          description: controller.error ?? 'Something went wrong.',
          footer: RetryButton(onPressed: controller.refresh),
        );
      case AppLoadState.ready:
        if (controller.filteredApps.isEmpty) {
          final searching = controller.searchText.trim().isNotEmpty;
          return CenteredStateMessage(
            icon: searching ? Icons.search_off : Icons.apps_outlined,
            title: searching ? 'No matching apps' : 'No apps found',
            description: searching
                ? 'Try a different search.'
                : 'This device has no apps to show.',
          );
        }
        return _buildApps(context);
    }
  }

  /// The recently-installed row (pinned: it stays put while the inventory
  /// under it scrolls) over the grid or list. The row steps aside while
  /// searching, where it would only repeat matches.
  Widget _buildApps(BuildContext context) {
    final searching = controller.searchText.trim().isNotEmpty;
    final recent = searching ? const <AppInfo>[] : controller.recentApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recent.isNotEmpty) _buildRecentRow(context, recent),
        Expanded(
          child: switch (controller.viewMode) {
            AppsViewMode.grid => _buildGrid(context),
            AppsViewMode.list => _buildList(),
          },
        ),
      ],
    );
  }

  Widget _buildRecentRow(BuildContext context, List<AppInfo> recent) {
    final theme = Theme.of(context);
    final iconSize = controller.iconSize.extent;
    final tileWidth = iconSize + 40;
    final tileHeight = appTileHeight(
      context,
      iconSize,
      theme.textTheme.bodySmall,
    );
    final expanded = controller.recentExpanded;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: controller.toggleRecentExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
              child: Row(
                children: [
                  // A section label over the tiles, not content: it steps
                  // down so the app names below read first.
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: context.eaglyTheme.tertiaryTextColor,
                  ),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      'Recently installed',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: context.eaglyTheme.secondaryTextColor,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: context.eaglyTheme.tertiaryTextColor,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            SizedBox(
              height: tileHeight + 8,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: recent.length,
                itemBuilder: (context, index) {
                  final app = recent[index];
                  return SizedBox(
                    width: tileWidth,
                    child: _buildTile(context, app, iconSize),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final apps = controller.filteredApps;
    final iconSize = controller.iconSize.extent;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: iconSize + 40,
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
        mainAxisExtent: appTileHeight(
          context,
          iconSize,
          Theme.of(context).textTheme.bodySmall,
        ),
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) =>
          _buildTile(context, apps[index], iconSize),
    );
  }

  Widget _buildTile(BuildContext context, AppInfo app, double iconSize) {
    return AppTile(
      key: ValueKey(app.packageName),
      controller: controller,
      app: app,
      iconSize: iconSize,
      onTap: controller.canLaunchApps ? () => _handleLaunch(app) : null,
      onSecondaryTap: (position) => _showContextMenu(context, position, app),
    );
  }

  Widget _buildList() {
    final apps = controller.filteredApps;
    final iconSize = controller.iconSize.extent;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return AppListRow(
          key: ValueKey(app.packageName),
          controller: controller,
          app: app,
          iconSize: iconSize,
          onTap: controller.canLaunchApps ? () => _handleLaunch(app) : null,
          onSecondaryTap: (position) =>
              _showContextMenu(context, position, app),
        );
      },
    );
  }

  void _showContextMenu(BuildContext context, Offset position, AppInfo app) {
    showAppContextMenu(
      context,
      position,
      controller: controller,
      app: app,
      actions: _actions,
      showSnackBar: _showSnackBar,
    );
  }
}

class const _Header({
  required final AppsController controller,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final title = controller.loadState == AppLoadState.ready
        ? 'Apps · ${controller.apps.length}'
        : 'Apps';

    return FeatureViewHeader(
      title: title,
      onClose: onClose,
      closeTooltip: 'Close apps pane',
      actions: [
        ToolbarAction(
          icon: Icons.refresh,
          label: 'Refresh',
          onPressed: controller.isLoading ? null : controller.refresh,
          busy: controller.isLoading,
        ),
      ],
    );
  }
}

class const _Toolbar({
  required final AppsController controller,
  required final TextEditingController searchController,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaneSearchBar(
      // The layout options and the system-apps toggle collapse into the
      // overflow menu before the search field is squeezed below its minimum
      // (the system-apps switch first, as a checked entry).
      child: OverflowToolbar(
        spacing: 0,
        flexibleMinWidth: 140,
        flexible: PaneSearchField(
          controller: searchController,
          onChanged: controller.setSearchText,
          hint: 'Search apps…',
        ),
        actions: [
          _viewModeAction(),
          _iconSizeAction(context),
          if (controller.canShowSystemApps)
            ToolbarAction(
              icon: Icons.settings_applications_outlined,
              label: 'System apps',
              isActive: controller.showSystemApps,
              onPressed: () =>
                  controller.setShowSystemApps(!controller.showSystemApps),
              barBuilder: (context, action) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Gap(12),
                  Text(action.label, style: theme.textTheme.bodySmall),
                  Switch(
                    value: controller.showSystemApps,
                    onChanged: controller.setShowSystemApps,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  ToolbarAction _viewModeAction() {
    final isList = controller.viewMode == AppsViewMode.list;
    return ToolbarAction(
      icon: isList ? Icons.grid_view : Icons.view_list,
      label: isList ? 'Grid view' : 'List view',
      tooltip: isList ? 'Show as grid' : 'Show as list with details',
      onPressed: () => controller.setViewMode(
        isList ? AppsViewMode.grid : AppsViewMode.list,
      ),
    );
  }

  /// A size picker in the bar; in the overflow menu, where an action can't
  /// open a submenu, the entry cycles to the next size instead.
  ToolbarAction _iconSizeAction(BuildContext context) {
    final current = controller.iconSize;
    final next =
        AppIconSize.values[(current.index + 1) % AppIconSize.values.length];
    return ToolbarAction(
      icon: Icons.photo_size_select_large,
      label: 'Icon size: ${current.label}',
      onPressed: () => controller.setIconSize(next),
      barBuilder: (context, action) => PopupMenuButton<AppIconSize>(
        tooltip: 'Icon size',
        iconSize: 20,
        icon: Icon(action.icon),
        initialValue: current,
        onSelected: controller.setIconSize,
        itemBuilder: (context) => [
          for (final size in AppIconSize.values)
            CheckedPopupMenuItem(
              value: size,
              checked: size == current,
              child: Text(size.label),
            ),
        ],
      ),
    );
  }
}
