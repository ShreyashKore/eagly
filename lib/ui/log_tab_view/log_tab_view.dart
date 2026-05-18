import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../constants/app_constants.dart';
import '../../constants/local_assets.dart';
import '../../data/device.dart';
import '../../data/log_entry.dart';
import '../../data/log_view_mode.dart';
import '../../features/app_log/app_logger.dart';
import '../../theme/app_theme.dart';
import '../../utils/log_feedback.dart';
import '../../utils/widget_extensions.dart';
import '../components/app_log_overlay.dart';
import '../log_viewer/log_viewer.dart';
import '../wireless_connection/wireless_connection_dialog.dart';
import 'components/available_device_card.dart';
import 'components/centered_state_message.dart';
import 'components/classic_filter_bar.dart';
import 'components/get_started_action_card.dart';
import 'components/inline_filter_bar.dart';
import 'components/log_search_bar.dart';
import 'components/scroll_to_end_button.dart';
import 'components/toolbar.dart';
import 'log_tab_controller.dart';
import 'log_tab_view_constants.dart';

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

  Future<void> _handleCopyAllLogs() async {
    final copiedCount = await controller.copyAllLogs();
    if (!mounted || copiedCount == 0) return;
    _showSnackBar(
      copiedCount == 1 ? 'Copied 1 log.' : 'Copied $copiedCount logs.',
    );
  }

  Future<void> _handleRowCopyAction(
    int? index,
    LogViewerCopyAction action,
  ) async {
    final format = switch (action) {
      LogViewerCopyAction.copyRow => LogCopyFormat.fullLine,
      LogViewerCopyAction.copyMessage => LogCopyFormat.messageOnly,
      LogViewerCopyAction.copyTimestampAndMessage =>
        LogCopyFormat.timestampAndMessage,
    };

    final copiedCount = await controller.copyRowsForContextMenu(
      clickedFilteredIndex: index,
      format: format,
    );
    if (!mounted || copiedCount == 0) return;

    final copiedLabel = switch (action) {
      LogViewerCopyAction.copyRow => 'row',
      LogViewerCopyAction.copyMessage => 'message',
      LogViewerCopyAction.copyTimestampAndMessage => 'time + message',
    };
    _showSnackBar(
      copiedCount == 1
          ? 'Copied $copiedLabel for 1 row.'
          : 'Copied $copiedLabel for $copiedCount rows.',
    );
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: controller.devices.isNotEmpty
                  ? Column(
                      key: const ValueKey('devices'),

                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    )
                  : (controller.isLoadingDevices ||
                        controller.hasAttemptedDeviceLoad)
                  ? Container(
                      key: const ValueKey('status-box'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: controller.isLoadingDevices
                            ? Column(
                                key: const ValueKey('loading'),
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const Gap(10),
                                  Text(
                                    'Searching for devices…',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const Gap(6),
                                  Text(
                                    'Looking for connected Android and iOS devices.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : Column(
                                key: const ValueKey('no-devices'),
                                children: [
                                  Icon(
                                    Icons.usb_off,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const Gap(10),
                                  Text(
                                    'No devices found',
                                    style: theme.textTheme.titleSmall,
                                  ),
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
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
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
      onUserScroll: controller.disableAutoScroll,
      rowSelectionMode: controller.rowSelectionMode,
      selectedRowIndices: controller.selectedRowIndices,
      onRowSelectionStart: controller.beginRowSelectionGesture,
      onSelectedRowsChanged: controller.setSelectedRows,
      onRowSelectionChanged: controller.setRowSelected,
      onRowCopyAction: _handleRowCopyAction,
      onSelectedTextChanged: controller.setSelectedSearchText,
      search: controller.appliedInlineSearch,
      currentMatchLogIndex:
          controller.searchBarVisible && controller.appliedInlineSearch.isActive
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
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.hardEdge,
                child: Image.asset(LocalAssets.appIcon, height: 96, width: 96),
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
        if (controller.hasVisibleWorkspace) _buildFilterArea(context),
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
      onCopyAll: controller.hasAnyCachedLogs
          ? () async {
              await _handleCopyAllLogs();
            }
          : null,
      onOpenSettings: widget.onOpenSettings,
    );
  }

  Widget _buildFilterArea(BuildContext context) {
    final isInline = controller.filterViewMode == LogFilterViewMode.inline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: isInline
                ? 'Inline filter mode active. Switch to classic fields.'
                : 'Classic filter mode active. Switch to inline filter.',
            onPressed: () {
              controller.setFilterViewMode(
                isInline ? LogFilterViewMode.classic : LogFilterViewMode.inline,
              );
            },
            icon: Icon(
              isInline ? Icons.filter_alt_outlined : Icons.filter_list_rounded,
            ),
          ),
          const Gap(4),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: isInline
                  ? InlineFilterBar(
                      key: const ValueKey('inline-filter-bar'),
                      controller: controller.inlineFilterController,
                      focusNode: controller.inlineFilterFocusNode,
                      onChanged: controller.onInlineFilterChanged,
                      onSubmitted: controller.applyFiltersNow,
                      onSuggestionApplied: controller.setInlineFilterText,
                      selectedLogLevel: controller.selectedLogLevel,
                      onLogLevelChanged: (level) {
                        if (level != null) {
                          controller.setSelectedLogLevel(level);
                        }
                      },
                      recentMessageFilters: controller.recentMessageFilters,
                      recentPackageFilters: controller.recentPackageFilters,
                      knownPackageFilters: controller.knownInlinePackageFilters,
                      recentPidTidFilters: controller.recentPidTidFilters,
                      recentTagFilters: controller.recentTagFilters,
                      isIos: controller.isIosLogContext,
                    )
                  : ClassicFilterBar(
                      key: const ValueKey('classic-filter-bar'),
                      messageController: controller.filterController,
                      messageFocusNode: controller.filterFocusNode,
                      onMessageFilterChanged: controller.onSearchChanged,
                      onMessageFilterSelected:
                          controller.selectMessageFilterSuggestion,
                      recentMessageFilters: controller.recentMessageFilters,
                      packageController: controller.packageFilterController,
                      packageFocusNode: controller.packageFilterFocusNode,
                      onPackageFilterChanged: controller.onPackageFilterChanged,
                      onPackageFilterSelected:
                          controller.selectPackageFilterSuggestion,
                      recentPackageFilters: controller.recentPackageFilters,
                      knownPackageFilters: controller.knownInlinePackageFilters,
                      pidTidController: controller.pidTidFilterController,
                      pidTidFocusNode: controller.pidTidFilterFocusNode,
                      onPidTidFilterChanged: controller.onPidTidFilterChanged,
                      onPidTidFilterSelected:
                          controller.selectPidTidFilterSuggestion,
                      recentPidTidFilters: controller.recentPidTidFilters,
                      tagController: controller.tagFilterController,
                      tagFocusNode: controller.tagFilterFocusNode,
                      onTagFilterChanged: controller.onTagFilterChanged,
                      onTagFilterSelected: controller.selectTagFilterSuggestion,
                      recentTagFilters: controller.recentTagFilters,
                      onSubmitFilters: controller.applyFiltersNow,
                      selectedLogLevel: controller.selectedLogLevel,
                      onLogLevelChanged: (level) {
                        if (level != null) {
                          controller.setSelectedLogLevel(level);
                        }
                      },
                      isIos: controller.isIosLogContext,
                    ),
            ),
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
                color: context.eaglyTheme.inlineNoticeBackground,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'No logs match your filter, but logs are being generated.',
                    style: TextStyle(
                      color: context.eaglyTheme.inlineNoticeForeground,
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
              search: controller.inlineSearch,
              hasError: controller.inlineSearchHasError,
              errorText: controller.inlineSearchErrorText,
              onSearchChanged: controller.updateInlineSearch,
              onSearchOptionsChanged: (search) =>
                  controller.updateInlineSearch(search, applyImmediately: true),
              onNext: controller.onSearchNext,
              onPrevious: controller.onSearchPrev,
              onClose: controller.closeSearchBar,
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
    final theme = context.eaglyTheme;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('Logs: ${controller.logs.length}', style: theme.statusBarStyle),
          const Gap(16),
          Text(
            'Filtered: ${controller.filteredLogs.length}',
            style: theme.statusBarStyle,
          ),
          if (controller.rowSelectionMode || controller.hasSelectedRows) ...[
            const Gap(16),
            Text(
              'Selected: ${controller.selectedRowCount}',
              style: theme.statusBarStyle,
            ),
          ],
          const Spacer(),
          Text(
            'App mem: ${controller.formatBytes(widget.appMemoryBytesListenable.value)}',
            style: theme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Logs mem: ${controller.formatBytes(controller.totalLogsMemoryBytes)}',
            style: theme.statusBarStyle,
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
              fontSize: 12,
              color: controller.isPaused
                  ? theme.statusPausedColor
                  : controller.isRunning
                  ? theme.statusLiveColor
                  : theme.statusStoppedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          ListenableBuilder(
            listenable: AppLogger.global.entriesListenable,
            builder: (context, _) {
              final hasWorkspaceErrors = AppLogger.global.hasEntries(
                sessionTag: controller.appLogSessionTag,
                errorsOnly: true,
              );
              if (!hasWorkspaceErrors) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Gap(8),
                  AppLogTriggerButton(
                    sessionTag: controller.appLogSessionTag,
                    title: 'App Logs • ${controller.title}',
                    tooltip: 'Show app errors for this tab',
                    iconSize: 16,
                  ),
                ],
              );
            },
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
                    fontSize: 12,
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
