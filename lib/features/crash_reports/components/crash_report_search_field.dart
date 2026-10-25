import 'package:flutter/material.dart';

import '../../../presentation/components/pane_search_field.dart';
import '../crash_report_controller.dart';

/// Filters the crash report list by process name, file name and body. Esc
/// clears it.
class const CrashReportSearchField({
  super.key,
  required final CrashReportController controller,
}) extends StatefulWidget {
  @override
  State<CrashReportSearchField> createState() => _CrashReportSearchFieldState();
}

class _CrashReportSearchFieldState extends State<CrashReportSearchField> {
  /// Seeded from the controller: the field is rebuilt each time the list
  /// comes back from a report, but the filter outlives it — an empty field
  /// over a filtered list would hide why reports are missing.
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.searchText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return PaneSearchBar(
      child: PaneSearchField(
        controller: _text,
        onChanged: controller.setSearchText,
        hint: 'Search crash reports…',
        busyMessage: controller.isSearchingContent
            ? 'Searching report contents…'
            : null,
      ),
    );
  }
}
