import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../file_manager_controller.dart';

/// Filters the current folder's listing as you type (see
/// [FileManagerController.filterText]). ↓ or Enter moves into the listing
/// with the first match selected; Esc clears the filter, and a second Esc
/// returns to the listing.
class const FileFilterField({
  super.key,
  required final FileManagerController controller,
  required final FocusNode focusNode,

  /// The listing's focus, handed over on ↓ / Enter / Esc.
  required final FocusNode listFocusNode,
  required final double width,
}) extends StatefulWidget {
  @override
  State<FileFilterField> createState() => _FileFilterFieldState();
}

class _FileFilterFieldState extends State<FileFilterField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.filterText,
  );

  FileManagerController get controller => widget.controller;

  @override
  void didUpdateWidget(FileFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The controller clears the filter on leaving the folder, and the
    // listing's Esc clears it too.
    if (_text.text != controller.filterText) {
      _text.value = TextEditingValue(
        text: controller.filterText,
        selection: TextSelection.collapsed(
          offset: controller.filterText.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _enterListing() {
    if (controller.reachableEntries.isEmpty) return;
    final selected = controller.selectedEntry;
    final reachable = controller.reachableEntries;
    if (selected == null || !reachable.any((e) => e.path == selected.path)) {
      controller.selectEntry(reachable.first);
    }
    widget.listFocusNode.requestFocus();
  }

  void _escape() {
    if (_text.text.isEmpty) {
      widget.listFocusNode.requestFocus();
    } else {
      _text.clear();
      controller.setFilterText('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = controller.filterText.isNotEmpty;
    final noMatches = hasText && controller.visibleCount == 0;
    return SizedBox(
      width: widget.width,
      height: context.scaled(30),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
          const SingleActivator(LogicalKeyboardKey.arrowDown): _enterListing,
        },
        child: TextField(
          controller: _text,
          focusNode: widget.focusNode,
          onChanged: controller.setFilterText,
          onSubmitted: (_) => _enterListing(),
          style: theme.textTheme.bodySmall,
          // The field fills the box's height, text centred — a single-line
          // field keeps its own height and sits at the box's top. Still one
          // line: a text keyboard, so Enter submits, and no newlines.
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Filter',
            filled: noMatches,
            fillColor: context.eaglyTheme.searchNoResultsFillColor,
            prefixIcon: const Icon(Icons.filter_list, size: 16),
            prefixIconConstraints: BoxConstraints(minWidth: context.scaled(28)),
            suffixIcon: hasText
                ? AppIconButton(
                    tooltip: 'Clear filter (Esc)',
                    iconSize: 14,
                    padding: 4,
                    onPressed: _escape,
                    icon: Icons.close,
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }
}
