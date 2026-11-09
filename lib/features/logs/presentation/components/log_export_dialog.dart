import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../presentation/components/saved_file_snack_bar.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../../../services/preferences_service.dart';
import '../../../../utils/log_feedback.dart';
import '../../../../utils/utils.dart';
import '../../data/models/log_column.dart';
import '../../log_controller.dart';
import '../../services/log_file_service.dart';

/// What the user picked in [showLogExportDialog].
class const LogExportChoice({
  required final LogExportScope scope,
  required final LogExportFormat format,

  /// Leave the columns hidden in the viewer out of a plain-text export.
  final bool visibleColumnsOnly = false,
});

/// Asks which entries to export and in which format, then exports them from
/// [controller]. A success shows a snack bar that opens the file or shows it
/// in its folder; a failure goes to [showMessage].
Future<void> exportLogsInteractively(
  BuildContext context,
  LogController controller, {
  required void Function(String message) showMessage,
}) async {
  final choice = await showLogExportDialog(
    context,
    allCount: controller.entriesForExport(LogExportScope.all).length,
    filteredCount: controller.entriesForExport(LogExportScope.filtered).length,
    selectedCount: controller.selectedRowCount,
    hiddenColumnLabels: [
      for (final column in LogColumn.values)
        if (!controller.visibleColumns.contains(column))
          column.labelFor(isIos: controller.isIosLogContext),
    ],
  );
  if (choice == null || !context.mounted) return;
  PreferencesService.logExportFormat = choice.format.name;

  final messenger = ScaffoldMessenger.of(context);
  final result = await controller.exportLogs(
    scope: choice.scope,
    format: choice.format,
    visibleColumnsOnly: choice.visibleColumnsOnly,
  );
  if (result.cancelled || !messenger.mounted) return;
  if (result.path case final path? when result.isSuccess) {
    await showSavedFileSnackBar(
      messenger,
      message: formatExportLogsMessage(result),
      path: path,
    );
  } else {
    showMessage(formatExportLogsMessage(result));
  }
}

/// The export options dialog. Completes with null when cancelled.
///
/// Starts on the narrowest scope that means something — the selected rows,
/// else the filtered view when a filter hides anything, else everything — and
/// on the format picked last time.
///
/// [hiddenColumnLabels] names the columns hidden in the viewer; when there are
/// any, a plain-text export offers to leave them out (and does by default).
Future<LogExportChoice?> showLogExportDialog(
  BuildContext context, {
  required int allCount,
  required int filteredCount,
  required int selectedCount,
  List<String> hiddenColumnLabels = const [],
}) {
  return showDialog<LogExportChoice>(
    context: context,
    builder: (context) => _LogExportDialog(
      allCount: allCount,
      filteredCount: filteredCount,
      selectedCount: selectedCount,
      hiddenColumnLabels: hiddenColumnLabels,
    ),
  );
}

class const _LogExportDialog({
  required final int allCount,
  required final int filteredCount,
  required final int selectedCount,
  required final List<String> hiddenColumnLabels,
}) extends StatefulWidget {
  @override
  State<_LogExportDialog> createState() => _LogExportDialogState();
}

class _LogExportDialogState extends State<_LogExportDialog> {
  late LogExportScope _scope = _isEnabled(LogExportScope.selected)
      ? LogExportScope.selected
      : _isEnabled(LogExportScope.filtered)
      ? LogExportScope.filtered
      : LogExportScope.all;
  late LogExportFormat _format = LogExportFormat.fromName(
    PreferencesService.logExportFormat,
  );
  var _visibleColumnsOnly = true;

  /// Whether the visible-columns option applies to the current choices.
  bool get _offersVisibleColumns =>
      _format == LogExportFormat.plainText &&
      widget.hiddenColumnLabels.isNotEmpty;

  int _count(LogExportScope scope) => switch (scope) {
    LogExportScope.all => widget.allCount,
    LogExportScope.filtered => widget.filteredCount,
    LogExportScope.selected => widget.selectedCount,
  };

  /// A filtered export that writes everything is just "All logs".
  bool _isEnabled(LogExportScope scope) => switch (scope) {
    LogExportScope.all => widget.allCount > 0,
    LogExportScope.filtered =>
      widget.filteredCount > 0 && widget.filteredCount < widget.allCount,
    LogExportScope.selected => widget.selectedCount > 0,
  };

  String _scopeSubtitle(LogExportScope scope) {
    if (_isEnabled(scope)) {
      return pluralize(_count(scope), 'entry', plural: 'entries');
    }
    return switch (scope) {
      LogExportScope.all => 'No logs yet',
      LogExportScope.filtered =>
        widget.filteredCount == 0
            ? 'Nothing matches the filters'
            : 'The filters hide nothing',
      LogExportScope.selected => 'No rows selected',
    };
  }

  void _submit() {
    if (!_isEnabled(_scope)) return;
    Navigator.of(context).pop(
      LogExportChoice(
        scope: _scope,
        format: _format,
        visibleColumnsOnly: _offersVisibleColumns && _visibleColumnsOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;
    final sectionStyle = theme.textTheme.labelLarge?.copyWith(
      color: eagly.secondaryTextColor,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: eagly.secondaryTextColor,
    );

    return AlertDialog(
      title: const Text('Export logs'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Include', style: sectionStyle),
              const Gap(4),
              RadioGroup<LogExportScope>(
                groupValue: _scope,
                onChanged: (value) {
                  if (value != null) setState(() => _scope = value);
                },
                child: Column(
                  children: [
                    for (final scope in LogExportScope.values)
                      RadioListTile<LogExportScope>(
                        value: scope,
                        enabled: _isEnabled(scope),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(scope.label),
                        subtitle: Text(
                          _scopeSubtitle(scope),
                          style: subtitleStyle,
                        ),
                      ),
                  ],
                ),
              ),
              const Gap(12),
              Text('Format', style: sectionStyle),
              const Gap(4),
              RadioGroup<LogExportFormat>(
                groupValue: _format,
                onChanged: (value) {
                  if (value != null) setState(() => _format = value);
                },
                child: Column(
                  children: [
                    for (final format in LogExportFormat.values)
                      RadioListTile<LogExportFormat>(
                        value: format,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(format.label),
                        subtitle: Text(
                          format.description,
                          style: subtitleStyle,
                        ),
                      ),
                  ],
                ),
              ),
              if (_offersVisibleColumns)
                CheckboxListTile(
                  value: _visibleColumnsOnly,
                  onChanged: (value) =>
                      setState(() => _visibleColumnsOnly = value ?? true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Only the columns shown in the viewer'),
                  subtitle: Text(
                    'Leaves out ${widget.hiddenColumnLabels.join(', ')}',
                    style: subtitleStyle,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: _isEnabled(_scope) ? _submit : null,
          child: const Text('Export…'),
        ),
      ],
    );
  }
}
