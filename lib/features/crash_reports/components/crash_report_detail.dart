import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:re_highlight/languages/json.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/code_view.dart';
import '../../../presentation/theme/app_theme.dart';
import '../crash_report_controller.dart';
import '../utils.dart';

/// The selected crash report in a [CodeView]. An `.ips` report (a JSON
/// header line, then a JSON body) is highlighted and shown pretty-printed,
/// with a toggle back to the file as written; a `.crash` report is plain text.
class const CrashReportDetail({
  super.key,
  required final CrashReportController controller,
}) extends StatefulWidget {
  @override
  State<CrashReportDetail> createState() => _CrashReportDetailState();
}

class _CrashReportDetailState extends State<CrashReportDetail> {
  /// Reports above this size are pretty-printed off the UI thread.
  static const _backgroundThreshold = 256 * 1024;

  String? _preparedFor;
  String? _pretty;
  bool _showPretty = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(CrashReportDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  Future<void> _prepare() async {
    final body = widget.controller.selectedReportBody;
    if (identical(body, _preparedFor)) return;
    _preparedFor = body;
    _pretty = null;
    if (body == null) return;
    final pretty = body.length > _backgroundThreshold
        ? await Isolate.run(() => CrashReportUtils.prettyIps(body))
        : CrashReportUtils.prettyIps(body);
    if (!mounted || !identical(body, _preparedFor)) return;
    setState(() => _pretty = pretty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.controller.selectedReport!;
    final body = widget.controller.selectedReportBody;
    if (body == null) return const Center(child: CircularProgressIndicator());

    final pretty = _pretty;
    final showPretty = _showPretty && pretty != null;
    return CodeView(
      text: showPretty ? pretty : body,
      language: pretty == null ? null : langJson,
      // A raw `.ips` body is one very long line.
      wordWrap: !showPretty,
      noun: 'report',
      // Opened from a filtered list, show where the search matched.
      initialFind: widget.controller.searchText.trim(),
      copyText: body,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              report.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              CrashReportUtils.formatTimestamp(report.timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.eaglyTheme.tertiaryTextColor,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (pretty != null)
          AppIconButton(
            tooltip: _showPretty ? 'Show as written' : 'Pretty-print',
            icon: Icons.data_object,
            iconSize: 16,
            padding: 4,
            isActive: _showPretty,
            onPressed: () => setState(() => _showPretty = !_showPretty),
          ),
      ],
    );
  }
}
