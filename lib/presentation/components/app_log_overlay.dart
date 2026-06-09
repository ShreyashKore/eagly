import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/app_log/app_logger.dart';

Future<void> showAppLogDialog(
  BuildContext context, {
  String? sessionTag,
  String title = 'App Logs',
  bool allowClear = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AppLogPanel(
        sessionTag: sessionTag,
        title: title,
        allowClear: allowClear,
      ),
    ),
  );
}

class AppLogTriggerButton extends StatelessWidget {
  const AppLogTriggerButton({
    super.key,
    this.sessionTag,
    required this.title,
    required this.tooltip,
    this.iconSize = 15,
    this.visualDensity = VisualDensity.compact,
  });

  final String? sessionTag;
  final String title;
  final String tooltip;
  final double iconSize;
  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLogger.global.entriesListenable,
      builder: (context, _) {
        final logger = AppLogger.global;
        final entries = logger.entriesWhere(sessionTag: sessionTag);
        final latest = logger.latestEntry(sessionTag: sessionTag) ??
            logger.latestEntry();
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final (icon, color) = _indicatorStyle(latest?.level, colorScheme);

        return IconButton(
          tooltip: latest == null ? tooltip : '$tooltip\n${latest.message}',
          visualDensity: visualDensity,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          onPressed: () => showAppLogDialog(
            context,
            sessionTag: sessionTag,
            title: title,
            allowClear: sessionTag == null,
          ),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: iconSize, color: color),
              if (entries.isNotEmpty)
                Positioned(
                  top: -2,
                  right: -3,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static (IconData, Color) _indicatorStyle(
    AppLogLevel? level,
    ColorScheme colorScheme,
  ) => switch (level) {
    AppLogLevel.error => (Icons.error_outline, colorScheme.error),
    AppLogLevel.warning => (Icons.warning_amber_outlined, colorScheme.tertiary),
    AppLogLevel.success => (Icons.check_circle_outline, Colors.green),
    AppLogLevel.info => (Icons.info_outline, colorScheme.primary),
    AppLogLevel.debug => (Icons.terminal, colorScheme.onSurfaceVariant),
    null => (Icons.terminal, colorScheme.onSurfaceVariant),
  };
}

class AppLogPanel extends StatefulWidget {
  const AppLogPanel({
    super.key,
    this.sessionTag,
    required this.title,
    this.allowClear = false,
  });

  final String? sessionTag;
  final String title;
  final bool allowClear;

  @override
  State<AppLogPanel> createState() => _AppLogPanelState();
}

class _AppLogPanelState extends State<AppLogPanel> {
  final ScrollController _scroll = ScrollController();
  bool _showAllLogs = false;

  @override
  void initState() {
    super.initState();
    AppLogger.global.entriesListenable.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    AppLogger.global.entriesListenable.removeListener(_onEntriesChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onEntriesChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copyVisible(BuildContext context) async {
    final entries = AppLogger.global.entriesWhere(
      sessionTag: widget.sessionTag,
      errorsOnly: !_showAllLogs,
    );
    await Clipboard.setData(
      ClipboardData(text: AppLogger.global.exportEntries(entries)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.sessionTag == null
              ? 'App logs copied to clipboard'
              : 'Session app logs copied to clipboard',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLogger.global.entriesWhere(
      sessionTag: widget.sessionTag,
      errorsOnly: !_showAllLogs,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 480,
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 13, color: colorScheme.onSurface),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                _HeaderButton(
                  icon: _showAllLogs ? Icons.filter_alt_off : Icons.filter_alt,
                  tooltip: _showAllLogs
                      ? 'Show only error logs'
                      : 'Show all logs',
                  onTap: () => setState(() => _showAllLogs = !_showAllLogs),
                  label: _showAllLogs ? 'All' : 'Errors',
                ),
                _HeaderButton(
                  icon: Icons.copy_outlined,
                  tooltip: 'Copy visible logs',
                  onTap: () => _copyVisible(context),
                ),
                if (widget.allowClear)
                  _HeaderButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Clear logs',
                    onTap: () {
                      AppLogger.global.clear();
                      setState(() {});
                    },
                  ),
                _HeaderButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.sessionTag == null
                          ? (_showAllLogs
                                ? 'No app logs yet.'
                                : 'No app errors yet.')
                          : (_showAllLogs
                                ? 'No app logs for this tab session yet.'
                                : 'No app errors for this tab session yet.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (_, index) => _LogEntryRow(
                      entry: entries[index],
                      showSessionTag: widget.sessionTag == null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({
    required this.entry,
    required this.showSessionTag,
  });

  final AppLogEntry entry;
  final bool showSessionTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (color, icon) = _levelStyle(entry.level, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level icon
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 5),
          // Timestamp
          Text(
            _formatTime(entry.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 5),
          // Source badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.source,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          // Session tag (optional)
          if (showSessionTag && entry.sessionTag != null) ...[
            const SizedBox(width: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.sessionTag!,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
          const SizedBox(width: 5),
          // Message — shown to user; detail is only in clipboard export.
          Expanded(
            child: Text(
              entry.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: entry.level == AppLogLevel.error
                    ? colorScheme.error
                    : entry.level == AppLogLevel.warning
                    ? colorScheme.tertiary
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (Color, IconData) _levelStyle(
    AppLogLevel level,
    ColorScheme colorScheme,
  ) => switch (level) {
    AppLogLevel.debug => (colorScheme.onSurfaceVariant, Icons.bug_report_outlined),
    AppLogLevel.info => (colorScheme.primary, Icons.info_outline),
    AppLogLevel.success => (Colors.green, Icons.check_circle_outline),
    AppLogLevel.warning => (colorScheme.tertiary, Icons.warning_amber_outlined),
    AppLogLevel.error => (colorScheme.error, Icons.error_outline),
  };

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

