import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../controllers/log_tab_controller.dart';
import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/log_view_mode.dart';
import '../theme/app_theme.dart';
import 'action_toolbar.dart';
import 'filter_bar.dart';
import 'log_search_bar.dart';
import 'log_viewer.dart';
import 'log_viewer_table.dart';
import 'log_viewer_worksheet.dart';
import 'scroll_to_end_button.dart';

class LogTabView extends StatefulWidget {
  const LogTabView({
    super.key,
    required this.controller,
    required this.appMemoryBytesListenable,
    required this.onOpenSettings,
    required this.onShowAbout,
  });

  final LogTabController controller;
  final ValueListenable<int> appMemoryBytesListenable;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowAbout;

  @override
  State<LogTabView> createState() => _LogTabViewState();
}

class _LogTabViewState extends State<LogTabView> {
  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  LogTabController get controller => widget.controller;

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleImportLogs() async {
    final result = await controller.importLogs();
    if (!mounted || result.cancelled || result.error == null) return;
    _showSnackBar(result.error!);
  }

  Future<void> _handleExportLogs() async {
    final result = await controller.exportLogs();
    if (!mounted || result.cancelled) return;

    final message =
        result.error ??
        (result.fileName == null
            ? 'Logs exported successfully.'
            : 'Logs exported to ${result.fileName}.');
    _showSnackBar(message);
  }

  Future<void> _handleLoadDevices({bool openPickerWhenNeeded = false}) async {
    await controller.loadDevices();
    if (!mounted || !openPickerWhenNeeded) return;
    if (controller.showGetStarted) return;
    if (controller.devices.length > 1 && controller.selectedDevice == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDevicesDropdown();
      });
    }
  }

  Future<void> _selectDevice(Device device) {
    return controller.selectDeviceAndStart(device);
  }

  void _openDevicesDropdown() {
    _dropdownButtonKey.currentContext?.visitChildElements((element) {
      if (element.widget is Semantics) {
        element.visitChildElements((element) {
          if (element.widget is Actions) {
            element.visitChildElements((element) {
              Actions.invoke(element, ActivateIntent());
            });
          }
        });
      }
    });
  }

  Widget _buildPrimaryActionButtons({bool compact = false}) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: [
        _GetStartedActionCard(
          icon: Icons.adb,
          title: 'Select device / Load devices',
          subtitle:
              'Discover connected devices and open a live logcat session.',
          onTap: () => _handleLoadDevices(openPickerWhenNeeded: compact),
        ),
        _GetStartedActionCard(
          icon: Icons.file_download_outlined,
          title: 'Import Logs',
          subtitle: 'Open a previously exported logcat JSON file in this tab.',
          onTap: () async {
            await _handleImportLogs();
          },
        ),
      ],
    );
  }

  Widget _buildGetStartedSecondaryActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Settings',
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          tooltip: 'About',
          onPressed: widget.onShowAbout,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    );
  }

  Widget _buildLogViewer(List<LogEntry> filtered, List<int> matches) {
    final safeIndex = matches.isEmpty
        ? null
        : controller.currentSearchMatchLogIndex(matches);

    switch (controller.viewMode) {
      case LogViewMode.text:
        return LogViewer(
          key: ValueKey('log-viewer-${controller.logViewerRevision}'),
          logs: filtered,
          scrollController: controller.scrollController,
          wrapText: controller.wrapText,
          onLogRowTap: controller.disableAutoScroll,
          searchQuery: controller.appliedInlineSearchQuery,
          caseSensitive: controller.searchCaseSensitive,
          currentMatchLogIndex:
              controller.searchBarVisible &&
                  controller.appliedInlineSearchQuery.isNotEmpty
              ? safeIndex
              : null,
          hiddenColumns: controller.hiddenColumns,
          columnWidths: controller.columnWidths,
          onHiddenColumnsChanged: controller.setHiddenColumns,
          onColumnWidthsChanged: controller.setColumnWidths,
        );
      case LogViewMode.dataTable:
        return LogViewerTable(
          logs: filtered,
          scrollController: controller.scrollController,
          onLogRowTap: controller.disableAutoScroll,
        );
      case LogViewMode.worksheet:
        return LogViewerWorksheet(
          logs: filtered,
          scrollController: controller.scrollController,
          onLogRowTap: controller.disableAutoScroll,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        widget.appMemoryBytesListenable,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: controller.showGetStarted
                ? _buildGetStarted(context)
                : _buildWorkspace(context),
          ),
        );
      },
    );
  }

  Widget _buildGetStarted(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surface,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _buildGetStartedSecondaryActions(),
            ),
            Icon(
              Icons.developer_board,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const Gap(18),
            Text(
              'ADB Logcat',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const Gap(28),
            _buildPrimaryActionButtons(),
            if (controller.devices.isNotEmpty) ...[
              const Gap(28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Available devices',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Gap(12),
              SingleChildScrollView(
                child: Column(
                  children: controller.devices
                      .map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AvailableDeviceCard(
                            device: device,
                            onSelected: () => _selectDevice(device),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ] else if (controller.hasAttemptedDeviceLoad &&
                !controller.isLoadingDevices) ...[
              const Gap(28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.usb_off,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const Gap(10),
                    Text('No devices found', style: theme.textTheme.titleSmall),
                    const Gap(6),
                    Text(
                      'Connect an Android device with ADB enabled.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        if (controller.hasVisibleWorkspace)
          FilterBar(
            filterQuery: controller.searchQuery,
            controller: controller.filterController,
            focusNode: controller.filterFocusNode,
            onFilterChanged: controller.onSearchChanged,
            selectedLogLevel: controller.selectedLogLevel,
            onLogLevelChanged: (level) {
              if (level != null) {
                controller.setSelectedLogLevel(level);
              }
            },
          ),
        Expanded(
          child: controller.hasVisibleWorkspace
              ? _buildViewerArea(context)
              : _buildNoDevicePlaceholder(context),
        ),
        _buildStatusBar(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;
    final selectedValue = controller.devices.firstWhereOrNull(
      (device) => device.id == controller.selectedDevice?.id,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        spacing: 4,
        children: [
          if (controller.devices.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    DropdownButton<Device>(
                      key: _dropdownButtonKey,
                      hint: const Text('Select Device'),
                      value: selectedValue,
                      underline: const SizedBox.shrink(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      isDense: true,
                      items: controller.devices
                          .map(
                            (device) => DropdownMenuItem(
                              value: device,
                              child: Text(
                                '${device.displayName} · ${device.status}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (device) {
                        if (device != null) {
                          _selectDevice(device);
                        }
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.all(0),
                      tooltip: 'Reload devices',
                      onPressed: _handleLoadDevices,
                      icon: const Icon(Icons.refresh),
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => _handleLoadDevices(openPickerWhenNeeded: true),
              icon: const Icon(Icons.usb),
              label: const Text('Load devices'),
            ),
          const Gap(4),
          IconButton(
            icon: Icon(
              Icons.play_arrow,
              color: controller.selectedDevice != null
                  ? logTheme.statusLiveColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.isRunning ? 'Restart' : 'Start',
            onPressed: controller.selectedDevice == null
                ? null
                : controller.startLogcat,
          ),
          IconButton(
            icon: Icon(
              controller.isPaused ? Icons.play_arrow : Icons.pause,
              color: controller.isRunning
                  ? logTheme.statusPausedColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: controller.isRunning
                ? (controller.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            onPressed: controller.isRunning
                ? controller.togglePauseResume
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: controller.logs.isNotEmpty
                ? 'Clear logs'
                : 'No logs to clear',
            onPressed: controller.logs.isNotEmpty ? controller.clearLogs : null,
          ),
          IconButton(
            icon: Icon(
              Icons.search,
              color: controller.searchBarVisible
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: controller.searchBarVisible
                ? 'Close search'
                : 'Search in logs (Ctrl+F / Cmd+F)',
            onPressed: controller.toggleSearchBar,
          ),
          const Spacer(),
          ActionToolbar(
            onImport: () async {
              await _handleImportLogs();
            },
            onExport: controller.logs.isEmpty
                ? null
                : () async {
                    await _handleExportLogs();
                  },
            wrapText: controller.wrapText,
            onToggleWrap: controller.toggleWrapText,
            autoScroll: controller.autoScroll,
            onToggleAutoScroll: controller.toggleAutoScroll,
            viewMode: controller.viewMode,
            onCycleViewMode: controller.cycleViewMode,
            openSettings: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildViewerArea(BuildContext context) {
    final filtered = controller.filteredLogs;
    final matches = controller.searchMatchIndices;

    return Stack(
      children: [
        _buildLogViewer(filtered, matches),
        if (controller.logs.isEmpty && controller.selectedDevice != null)
          _CenteredStateMessage(
            icon: controller.isRunning ? Icons.sync : Icons.play_circle_outline,
            title: controller.isRunning
                ? 'Waiting for logs from ${controller.selectedDevice!.displayName}'
                : 'Ready to capture logs',
            description: controller.isRunning
                ? 'Keep this tab open while logcat streams from the selected device.'
                : 'Press the play button to start streaming logcat output for the selected device.',
          ),
        if (controller.logs.isNotEmpty && filtered.isEmpty)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: context.logViewTheme.inlineNoticeBackground,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'No logs match your filter, but logs are being generated.',
                    style: TextStyle(
                      color: context.logViewTheme.inlineNoticeForeground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (controller.searchBarVisible)
          Positioned(
            top: 24,
            right: 12,
            child: LogSearchBar(
              controller: controller.searchController,
              focusNode: controller.searchFocusNode,
              caseSensitive: controller.searchCaseSensitive,
              onQueryChanged: controller.onInlineSearchChanged,
              onCaseSensitiveChanged: controller.setSearchCaseSensitive,
              onNext: controller.onSearchNext,
              onPrevious: controller.onSearchPrev,
              onClose: controller.toggleSearchBar,
              totalMatches: matches.length,
              currentMatch: matches.isEmpty
                  ? 0
                  : controller.searchCurrentMatch + 1,
            ),
          ),
        ListenableBuilder(
          listenable: controller.scrollController,
          builder: (context, child) {
            return ScrollToEndButton(
              visible:
                  controller.logs.isNotEmpty &&
                  controller.scrollController.hasClients &&
                  controller.scrollController.offset <
                      (controller.scrollController.position.maxScrollExtent -
                          24),
              onPressed: controller.scrollToEnd,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoDevicePlaceholder(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _CenteredStateMessage(
          icon: Icons.devices_outlined,
          title: 'No device or imported logs in this tab',
          description:
              'Load connected devices to begin a live session, or import a saved log file into this workspace.',
          footer: _buildPrimaryActionButtons(compact: true),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final logTheme = context.logViewTheme;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            'Logs: ${controller.logs.length}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Filtered: ${controller.filteredLogs.length}',
            style: logTheme.statusBarStyle,
          ),
          const Spacer(),
          Text(
            'App mem: ${controller.formatBytes(widget.appMemoryBytesListenable.value)}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Logs mem: ${controller.formatBytes(controller.totalLogsMemoryBytes)}',
            style: logTheme.statusBarStyle,
          ),
          const Gap(8),
          _buildLogLinesEditor(context),
          const Gap(8),
          SizedBox(
            height: 18,
            child: VerticalDivider(
              width: 2,
              thickness: 2,
              radius: BorderRadius.circular(2),
            ),
          ),
          const Gap(8),
          Text(
            controller.isPaused
                ? 'Paused'
                : controller.isRunning
                ? 'Live'
                : 'Stopped',
            style: TextStyle(
              color: controller.isPaused
                  ? logTheme.statusPausedColor
                  : controller.isRunning
                  ? logTheme.statusLiveColor
                  : logTheme.statusStoppedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLinesEditor(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: controller.editingLogLinesLimit
          ? null
          : BoxDecoration(
              color: Colors.pink,
              borderRadius: BorderRadius.circular(4),
            ),
      child: !controller.editingLogLinesLimit
          ? InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => controller.setEditingLogLinesLimit(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Max lines: ${controller.logLinesLimit}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicWidth(
                  child: TextField(
                    onTapOutside: (_) =>
                        controller.setEditingLogLinesLimit(false),
                    controller: controller.logLinesController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      prefixText: 'Max lines: ',
                      border: OutlineInputBorder(),
                      suffix: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: controller.submitLogLinesLimit,
                        icon: const Icon(Icons.check, size: 14),
                      ),
                    ),
                    onSubmitted: controller.submitLogLinesLimit,
                    onEditingComplete: () =>
                        controller.setEditingLogLinesLimit(false),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AvailableDeviceCard extends StatelessWidget {
  const _AvailableDeviceCard({required this.device, required this.onSelected});

  final Device device;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelected,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_android, color: theme.colorScheme.primary),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.displayName, style: theme.textTheme.titleSmall),
                    const Gap(4),
                    Text(
                      '${device.id} · ${device.status}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GetStartedActionCard extends StatelessWidget {
  const _GetStartedActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logTheme = context.logViewTheme;

    return SizedBox(
      width: 320,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  color: logTheme.cardShadowColor,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const Gap(14),
                Text(title, style: theme.textTheme.titleMedium),
                const Gap(8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredStateMessage extends StatelessWidget {
  const _CenteredStateMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const Gap(16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (footer != null) ...[const Gap(20), footer!],
          ],
        ),
      ),
    );
  }
}
