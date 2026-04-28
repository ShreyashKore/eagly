import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../controllers/log_tab_controller.dart';
import '../constants/app_constants.dart';
import '../data/device.dart';
import '../data/log_entry.dart';
import '../theme/app_theme.dart';
import '../utils/log_feedback.dart';
import '../utils/widget_extensions.dart';
import 'filter_bar.dart';
import 'log_tab_view/available_device_card.dart';
import 'log_tab_view/centered_state_message.dart';
import 'log_tab_view/get_started_action_card.dart';
import 'log_tab_view/log_tab_view_constants.dart';
import 'log_search_bar.dart';
import 'log_viewer.dart';
import 'scroll_to_end_button.dart';
import 'toolbar.dart';
import 'wireless_connection_dialog.dart';

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

    _showSnackBar(formatExportLogsMessage(result));
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

  Future<void> _showWirelessConnectionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return WirelessConnectionDialog(
          controller: controller,
          wirelessController: controller.wirelessController,
          onShowSnackBar: _showSnackBar,
        );
      },
    );
  }

  Future<void> _selectDevice(Device device) {
    return controller.selectDeviceAndStart(device);
  }

  void _openDevicesDropdown() {
    _dropdownButtonKey.openDropdown();
  }

  Widget _buildGettingStartedOptions({bool compact = false}) {
    final theme = Theme.of(context);
    return Column(
      spacing: 16,
      children: [
        GetStartedActionCard(
          icon: Icons.phone_android_rounded,
          title: 'Select device',
          subtitle:
              'Discover connected Android and iOS devices and open a live log stream.',
          onTap: () => _handleLoadDevices(openPickerWhenNeeded: compact),
          secondaryActions: [
            FilledButton.tonalIcon(
              onPressed: () => _handleLoadDevices(openPickerWhenNeeded: true),
              icon: const Icon(Icons.usb),
              label: const Text('Load devices'),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.wifi_tethering_outlined),
              onPressed: _showWirelessConnectionDialog,
              label: const Text('Wireless ADB'),
            ),
          ],
          children: [
            if (controller.devices.isNotEmpty) ...[
              const Gap(4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Available devices',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              SingleChildScrollView(
                child: Column(
                  spacing: 8,
                  children: controller.devices
                      .map(
                        (device) => AvailableDeviceCard(
                          device: device,
                          onSelected: () => _selectDevice(device),
                          onShowMessage: _showSnackBar,
                        ),
                      )
                      .toList(),
                ),
              ),
            ] else if (controller.hasAttemptedDeviceLoad &&
                !controller.isLoadingDevices) ...[
              const Gap(8),
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
                      'Connect an Android device with ADB enabled, or an iOS device supported by libimobiledevice.',
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
        GetStartedActionCard(
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
      spacing: 8,
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
        constraints: const BoxConstraints(
          maxWidth: LogTabViewConstants.getStartedMaxWidth,
        ),
        child: SingleChildScrollView(
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
                AppConstants.appName,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const Gap(28),
              _buildGettingStartedOptions(),
            ],
          ),
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
              : SingleChildScrollView(
                  child: _buildNoDevicePlaceholder(context),
                ),
        ),
        if (controller.hasVisibleWorkspace) _buildStatusBar(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Toolbar(
      controller: controller,
      dropdownButtonKey: _dropdownButtonKey,
      onLoadDevices: _handleLoadDevices,
      onShowWirelessConnectionDialog: _showWirelessConnectionDialog,
      onSelectDevice: _selectDevice,
      onImport: () async {
        await _handleImportLogs();
      },
      onExport: controller.logs.isEmpty
          ? null
          : () async {
              await _handleExportLogs();
            },
      onOpenSettings: widget.onOpenSettings,
    );
  }

  Widget _buildViewerArea(BuildContext context) {
    final filtered = controller.filteredLogs;
    final matches = controller.searchMatchIndices;

    return Stack(
      children: [
        _buildLogViewer(filtered, matches),
        if (controller.logs.isEmpty && controller.selectedDevice != null)
          CenteredStateMessage(
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
        constraints: const BoxConstraints(
          maxWidth: LogTabViewConstants.noDevicePlaceholderMaxWidth,
        ),
        child: CenteredStateMessage(
          icon: Icons.devices_outlined,
          title: 'No device or imported logs in this tab',
          description:
              'Load connected devices to begin a live session, or import a saved log file into this workspace.',
          footer: _buildGettingStartedOptions(compact: true),
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
          : BoxDecoration(borderRadius: BorderRadius.circular(4)),
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
