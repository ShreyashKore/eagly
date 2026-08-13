import 'package:eagly/presentation/components/feature_view.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/centered_state_message.dart';
import 'apps_controller.dart';
import 'components/app_context_menu.dart';
import 'components/app_tile.dart';
import 'data/app_info.dart';

/// Apps feature pane: lists installed apps as an icon grid with search and
/// (Android) a system-apps toggle, and drives the per-app context menu
/// actions. Owns the confirmation dialogs and snackbars for destructive
/// actions. [onClose] hides the pane (handled by the device screen).
class AppsFeatureView extends FeatureView {
  const AppsFeatureView({
    super.key,
    required this.controller,
    required super.onClose,
  });

  final AppsController controller;

  @override
  State<AppsFeatureView> createState() => _AppsFeatureViewState();
}

class _AppsFeatureViewState extends State<AppsFeatureView> {
  AppsController get controller => widget.controller;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String? message) {
    if (message == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
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
    final confirmed = await _confirmDestructive(
      title: 'Clear data for ${app.displayName}?',
      message:
          "This permanently deletes the app's data and cache on the device. "
          'It will restart as if freshly installed.',
      confirmLabel: 'Clear Data',
    );
    if (!confirmed) return;
    _showSnackBar(await controller.clearData(app));
  }

  Future<void> _handleUninstall(AppInfo app) async {
    final confirmed = await _confirmDestructive(
      title: 'Uninstall ${app.displayName}?',
      message: 'This permanently removes the app and its data from the device.',
      confirmLabel: 'Uninstall',
    );
    if (!confirmed) return;
    _showSnackBar(await controller.uninstall(app));
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

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
                    if (controller.isBusy) _buildBusyOverlay(context),
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
        return _buildGrid();
      case AppLoadState.error:
        return CenteredStateMessage(
          icon: Icons.apps_outlined,
          title: 'Could not load apps',
          description: controller.error ?? 'Something went wrong.',
          footer: FilledButton.icon(
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
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
        return _buildGrid();
    }
  }

  Widget _buildGrid() {
    final apps = controller.filteredApps;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 92,
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
        childAspectRatio: 0.8,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return AppTile(
          key: ValueKey(app.packageName),
          controller: controller,
          app: app,
          onTap: controller.canLaunchApps ? () => _handleLaunch(app) : null,
          onSecondaryTap: (position) => showAppContextMenu(
            context,
            position,
            controller: controller,
            app: app,
            actions: _actions,
          ),
        );
      },
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
                  const Gap(12),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});

  final AppsController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = controller.loadState == AppLoadState.ready
        ? 'Apps · ${controller.apps.length}'
        : 'Apps';

    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.isLoading ? null : controller.refresh,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close apps pane',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.searchController});

  final AppsController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: searchController,
                onChanged: controller.setSearchText,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search apps…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
          if (controller.canShowSystemApps) ...[
            const Gap(12),
            Text('System apps', style: theme.textTheme.bodySmall),
            Switch(
              value: controller.showSystemApps,
              onChanged: controller.setShowSystemApps,
            ),
          ],
        ],
      ),
    );
  }
}
