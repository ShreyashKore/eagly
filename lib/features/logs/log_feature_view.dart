import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../data/log_entry.dart';
import '../../data/log_view_mode.dart';
import '../../features/app_log/app_logger.dart';
import '../../session/device_session_controller.dart';
import '../../theme/app_theme.dart';
import '../../ui/components/app_log_overlay.dart';
import '../../ui/components/centered_state_message.dart';
import '../../ui/log_viewer/log_viewer.dart';
import '../../utils/log_entry_utils.dart';
import '../../utils/log_feedback.dart';
import '../../utils/utils.dart';
import 'components/classic_filter_bar.dart';
import 'components/inline_filter_bar.dart';
import 'components/log_search_bar.dart';
import 'components/scroll_to_end_button.dart';
import 'components/toolbar.dart';
import 'log_controller.dart';

/// The Logs feature pane for a single device: toolbar, filter area, the log
/// viewer (with empty/search/scroll overlays), and a status bar.
class LogFeatureView extends StatefulWidget {
  const LogFeatureView({
    super.key,
    required this.controller,
    required this.session,
    required this.appMemoryBytesListenable,
  });

  final LogController controller;
  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;

  @override
  State<LogFeatureView> createState() => _LogFeatureViewState();
}

class _LogFeatureViewState extends State<LogFeatureView> {
  var _isInstallDropActive = false;

  LogController get controller => widget.controller;
  DeviceSessionController get session => widget.session;

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleExportLogs() async {
    final result = await controller.exportLogs();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatExportLogsMessage(result));
  }

  Future<void> _handleInstallApp() async {
    final result = await session.installAppFromPicker();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatAppInstallMessage(result));
  }

  Future<void> _handleInstallDrop(List<String> paths) async {
    final result = await session.installDroppedPaths(paths);
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatAppInstallMessage(result));
  }

  void _setInstallDropActive(bool value) {
    if (_isInstallDropActive == value) return;
    setState(() => _isInstallDropActive = value);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        session,
        widget.appMemoryBytesListenable,
      ]),
      builder: (context, _) {
        return Column(
          children: [
            _buildToolbar(context),
            _buildFilterArea(context),
            Expanded(child: _buildViewerArea(context)),
            _buildStatusBar(context),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Toolbar(
      controller: controller,
      session: session,
      onInstallApp: session.isConnected
          ? () async => _handleInstallApp()
          : null,
      onInstallDrop: _handleInstallDrop,
      onInstallDropActiveChanged: _setInstallDropActive,
      isInstallDropActive: _isInstallDropActive,
      onExport: controller.logs.isEmpty
          ? null
          : () async => _handleExportLogs(),
      onCopyAll: controller.hasAnyCachedLogs
          ? () async => _handleCopyAllLogs()
          : null,
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
    return _buildLogViewerStack(filtered, matches);
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
      onToggleRowSelectionMode: controller.toggleRowSelectionMode,
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

  Widget _buildLogViewerStack(List<LogEntry> filtered, List<int> matches) {
    return Stack(
      children: [
        _buildLogViewer(filtered, matches),
        if (controller.logs.isEmpty)
          CenteredStateMessage(
            icon: controller.isRunning ? Icons.sync : Icons.play_circle_outline,
            title: controller.isRunning
                ? 'Waiting for logs from ${session.device.displayName}'
                : 'Ready to capture logs',
            description: controller.isRunning
                ? 'Keep this tab open while logs stream from the device.'
                : 'Press the play button to start streaming logs for this device.',
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No logs match your filter, but logs are being generated.',
                        style: TextStyle(
                          color: context.eaglyTheme.inlineNoticeForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: controller.clearFilter,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              context.eaglyTheme.inlineNoticeForeground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Clear filter'),
                      ),
                    ],
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
            'App mem: ${formatBytes(widget.appMemoryBytesListenable.value)}',
            style: theme.statusBarStyle,
          ),
          const Gap(16),
          Text(
            'Logs mem: ${formatBytes(controller.totalLogsMemoryBytes)}',
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
                    title: 'App Logs • ${session.device.displayName}',
                    tooltip: 'Show app errors for this device',
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
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 4,
                      ),
                      prefixText: 'Max lines: ',
                      border: const OutlineInputBorder(),
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
