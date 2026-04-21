import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../controllers/log_tab_controller.dart';
import '../data/device.dart';
import '../data/log_entry.dart';
import '../data/log_view_mode.dart';
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
  });

  final LogTabController controller;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  State<LogTabView> createState() => _LogTabViewState();
}

class _LogTabViewState extends State<LogTabView> {
  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  LogTabController get controller => widget.controller;

  Future<void> _handleLoadDevices({bool openPickerWhenNeeded = false}) async {
    await controller.loadDevices();
    if (!mounted || !openPickerWhenNeeded) return;
    if (controller.devices.length > 1 && controller.selectedDevice == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDevicesDropdown();
      });
    }
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
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
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
            theme.colorScheme.primary.withValues(alpha: 0.06),
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
            Icon(
              Icons.developer_board,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const Gap(18),
            Text(
              'Get started with ADB Logcat',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              'Open a device session or import a saved log file. Once you pick an option, this tab becomes a regular workspace.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(28),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _GetStartedActionCard(
                  icon: Icons.adb,
                  title: 'Select device / Load devices',
                  subtitle: 'Discover connected devices and open a live logcat session.',
                  onTap: () => _handleLoadDevices(openPickerWhenNeeded: true),
                ),
                _GetStartedActionCard(
                  icon: Icons.file_download_outlined,
                  title: 'Import Logs',
                  subtitle: 'Open a previously exported logcat JSON file in this tab.',
                  onTap: controller.importLogs,
                ),
              ],
            ),
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
    final selectedValue = controller.devices.firstWhereOrNull(
      (device) => device.id == controller.selectedDevice?.id,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: DropdownButton<Device>(
                key: _dropdownButtonKey,
                hint: const Text('Select Device'),
                value: selectedValue,
                underline: const SizedBox.shrink(),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                isDense: true,
                items: controller.devices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device,
                        child: Text('${device.displayName} · ${device.status}'),
                      ),
                    )
                    .toList(),
                onChanged: controller.setSelectedDevice,
              ),
            ),
          ),
          const Gap(8),
          if (controller.devices.isNotEmpty)
            IconButton(
              tooltip: 'Reload devices',
              onPressed: _handleLoadDevices,
              icon: const Icon(Icons.refresh),
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
                  ? Colors.green
                  : Colors.grey,
            ),
            tooltip: controller.isRunning ? 'Restart' : 'Start',
            onPressed:
                controller.selectedDevice == null ? null : controller.startLogcat,
          ),
          IconButton(
            icon: Icon(
              controller.isPaused ? Icons.play_arrow : Icons.pause,
              color: controller.isRunning ? Colors.orange : Colors.grey,
            ),
            tooltip: controller.isRunning
                ? (controller.isPaused ? 'Resume' : 'Pause')
                : 'Not running',
            onPressed: controller.isRunning ? controller.togglePauseResume : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: controller.logs.isNotEmpty ? 'Clear logs' : 'No logs to clear',
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
            onImport: controller.importLogs,
            onExport: controller.logs.isEmpty ? null : controller.exportLogs,
            wrapText: controller.wrapText,
            onToggleWrap: controller.toggleWrapText,
            autoScroll: controller.autoScroll,
            onToggleAutoScroll: controller.toggleAutoScroll,
            viewMode: controller.viewMode,
            onCycleViewMode: controller.cycleViewMode,
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
                color: Colors.yellow[100],
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'No logs match your filter, but logs are being generated.',
                    style: TextStyle(
                      color: Colors.black87,
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
              currentMatch: matches.isEmpty ? 0 : controller.searchCurrentMatch + 1,
            ),
          ),
        ListenableBuilder(
          listenable: controller.scrollController,
          builder: (context, child) {
            return ScrollToEndButton(
              visible: controller.logs.isNotEmpty &&
                  controller.scrollController.hasClients &&
                  controller.scrollController.offset <
                      (controller.scrollController.position.maxScrollExtent - 24),
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
          footer: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _handleLoadDevices(openPickerWhenNeeded: true),
                icon: const Icon(Icons.usb),
                label: const Text('Load devices'),
              ),
              OutlinedButton.icon(
                onPressed: controller.importLogs,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import logs'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('Logs: ${controller.logs.length}', style: const TextStyle(fontSize: 13)),
          const Gap(16),
          Text(
            'Filtered: ${controller.filteredLogs.length}',
            style: const TextStyle(fontSize: 13),
          ),
          const Gap(16),
          Text(
            'App mem: ${controller.formatBytes(widget.appMemoryBytesListenable.value)}',
            style: const TextStyle(fontSize: 13),
          ),
          const Gap(16),
          Text(
            'Logs mem: ${controller.formatBytes(controller.totalLogsMemoryBytes)}',
            style: const TextStyle(fontSize: 13),
          ),
          const Gap(16),
          _buildLogLinesEditor(context),
          const Spacer(),
          Text(
            controller.isPaused
                ? 'Paused'
                : controller.isRunning
                ? 'Live'
                : 'Stopped',
            style: TextStyle(
              color: controller.isPaused
                  ? Colors.orange[700]
                  : controller.isRunning
                  ? Colors.green[700]
                  : Colors.red[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLinesEditor(BuildContext context) {
    return Container(
      width: controller.editingLogLinesLimit ? 210 : null,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: controller.editingLogLinesLimit
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  style: const TextStyle(
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    color: Colors.blue,
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicWidth(
                  child: TextField(
                    onTapOutside: (_) => controller.setEditingLogLinesLimit(false),
                    controller: controller.logLinesController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      prefixText: 'Max lines: ',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: controller.submitLogLinesLimit,
                    onEditingComplete: () => controller.setEditingLogLinesLimit(false),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: controller.submitLogLinesLimit,
                  icon: const Icon(Icons.check, size: 14),
                ),
              ],
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
                  color: Colors.black.withValues(alpha: 0.04),
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
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const Gap(8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (footer != null) ...[
              const Gap(20),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}



