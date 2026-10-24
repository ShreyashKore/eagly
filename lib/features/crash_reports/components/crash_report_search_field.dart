import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
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

  void _clear() {
    _text.clear();
    widget.controller.setSearchText('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final hasText = controller.searchText.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: context.scaled(34),
        child: CallbackShortcuts(
          bindings: {
            if (hasText)
              const SingleActivator(LogicalKeyboardKey.escape): _clear,
          },
          child: TextField(
            controller: _text,
            onChanged: controller.setSearchText,
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search crash reports…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: !hasText
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (controller.isSearchingContent)
                          Tooltip(
                            message: 'Searching report contents…',
                            child: SizedBox.square(
                              dimension: context.scaled(12),
                              child: const CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                          ),
                        AppIconButton(
                          tooltip: 'Clear search',
                          iconSize: 15,
                          padding: 4,
                          onPressed: _clear,
                          icon: Icons.close,
                        ),
                      ],
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ),
    );
  }
}
