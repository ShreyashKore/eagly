import 'package:flutter/material.dart';

import '../../../constants/log_constants.dart';
import '../../../data/log_level.dart';

// Consistent height for all filter bar inputs.
const double _kFilterFieldHeight = 36.0;

InputDecoration _filterInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  IconData? prefixIcon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  InputBorder inputBorder(Color color) =>
      OutlineInputBorder(borderSide: BorderSide(color: color, width: 1.5));
  return InputDecoration(
    labelText: labelText,
    labelStyle: const TextStyle(fontSize: 12),
    hintText: hintText,
    hintStyle: const TextStyle(fontSize: 12),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: inputBorder(Colors.transparent),
    enabledBorder: inputBorder(Colors.transparent),
    focusedBorder: inputBorder(colorScheme.primary),
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest,
    prefixIconConstraints: prefixIcon != null
        ? const BoxConstraints(minHeight: 28, minWidth: 28)
        : null,
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 14) : null,
  );
}

class ClassicFilterBar extends StatelessWidget {
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final ValueChanged<String> onMessageFilterChanged;
  final ValueChanged<String> onMessageFilterSelected;
  final List<String> recentMessageFilters;
  final TextEditingController packageController;
  final FocusNode packageFocusNode;
  final ValueChanged<String> onPackageFilterChanged;
  final ValueChanged<String> onPackageFilterSelected;
  final List<String> recentPackageFilters;
  final TextEditingController pidTidController;
  final FocusNode pidTidFocusNode;
  final ValueChanged<String> onPidTidFilterChanged;
  final ValueChanged<String> onPidTidFilterSelected;
  final List<String> recentPidTidFilters;
  final TextEditingController tagController;
  final FocusNode tagFocusNode;
  final ValueChanged<String> onTagFilterChanged;
  final ValueChanged<String> onTagFilterSelected;
  final List<String> recentTagFilters;
  final VoidCallback onSubmitFilters;
  final LogLevel selectedLogLevel;
  final ValueChanged<LogLevel?> onLogLevelChanged;
  final bool isIos;

  const ClassicFilterBar({
    super.key,
    required this.messageController,
    required this.messageFocusNode,
    required this.onMessageFilterChanged,
    required this.onMessageFilterSelected,
    required this.recentMessageFilters,
    required this.packageController,
    required this.packageFocusNode,
    required this.onPackageFilterChanged,
    required this.onPackageFilterSelected,
    required this.recentPackageFilters,
    required this.pidTidController,
    required this.pidTidFocusNode,
    required this.onPidTidFilterChanged,
    required this.onPidTidFilterSelected,
    required this.recentPidTidFilters,
    required this.tagController,
    required this.tagFocusNode,
    required this.onTagFilterChanged,
    required this.onTagFilterSelected,
    required this.recentTagFilters,
    required this.onSubmitFilters,
    required this.selectedLogLevel,
    required this.onLogLevelChanged,
    this.isIos = false,
  });

  @override
  Widget build(BuildContext context) {
    return _buildRow(
      context: context,
      items: buildLogLevelDropdownItems(
        includeValueInLabel: true,
        isIos: isIos,
      ),
      currentValue: selectedLogLevel.normalizeSelectionForPlatform(
        isIos: isIos,
      ),
      onChanged: onLogLevelChanged,
    );
  }

  Widget _buildRow({
    required BuildContext context,
    required List<DropdownMenuItem<LogLevel>> items,
    required LogLevel currentValue,
    required ValueChanged<LogLevel?> onChanged,
  }) {
    return Row(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: _kFilterFieldHeight,
            child: DropdownButtonFormField<LogLevel>(
              initialValue: currentValue,
              isExpanded: true,
              isDense: true,
              decoration: _filterInputDecoration(context, labelText: 'Level'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              items: buildLogLevelDropdownItems(
                includeValueInLabel: true,
                isIos: isIos,
              ),
              onChanged: onLogLevelChanged,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _RecentFilterField(
            controller: packageController,
            focusNode: packageFocusNode,
            onChanged: onPackageFilterChanged,
            onSuggestionSelected: onPackageFilterSelected,
            onSubmitted: (_) => onSubmitFilters(),
            recentValues: recentPackageFilters,
            labelText: 'Package',
            hintText: 'Package / process',
            prefixIcon: Icons.apps_outlined,
          ),
        ),
        Expanded(
          flex: 3,
          child: _RecentFilterField(
            controller: tagController,
            focusNode: tagFocusNode,
            onChanged: onTagFilterChanged,
            onSuggestionSelected: onTagFilterSelected,
            onSubmitted: (_) => onSubmitFilters(),
            recentValues: recentTagFilters,
            labelText: 'Tag',
            hintText: 'Filter tag…',
            prefixIcon: Icons.sell_outlined,
          ),
        ),
        Expanded(
          flex: 10,
          child: _RecentFilterField(
            controller: messageController,
            focusNode: messageFocusNode,
            onChanged: onMessageFilterChanged,
            onSuggestionSelected: onMessageFilterSelected,
            onSubmitted: (_) => onSubmitFilters(),
            recentValues: recentMessageFilters,
            labelText: 'Message',
            hintText: 'Filter message text…',
            prefixIcon: Icons.message_outlined,
          ),
        ),
      ],
    );
  }
}

class _RecentFilterField extends StatelessWidget {
  const _RecentFilterField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSuggestionSelected,
    required this.onSubmitted,
    required this.recentValues,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSuggestionSelected;
  final ValueChanged<String> onSubmitted;
  final List<String> recentValues;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;

  List<String> _matchingOptions(String query) {
    final q = query.trim().toLowerCase();
    return recentValues
        .where((v) {
          if (q.isEmpty) return true;
          return v.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFilterFieldHeight,
      child: RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: focusNode,
        optionsBuilder: (textEditingValue) =>
            _matchingOptions(textEditingValue.text),
        onSelected: (value) {
          controller.text = value;
          onSuggestionSelected(value);
        },
        fieldViewBuilder:
            (context, fieldController, fieldFocusNode, onFieldSubmitted) {
              return TextField(
                controller: fieldController,
                focusNode: fieldFocusNode,
                style: const TextStyle(fontSize: 12),
                decoration: _filterInputDecoration(
                  context,
                  labelText: labelText,
                  hintText: hintText,
                  prefixIcon: prefixIcon,
                ),
                onChanged: onChanged,
                onSubmitted: (value) {
                  onSubmitted(value);
                  onFieldSubmitted();
                },
              );
            },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 220,
                  maxWidth: 320,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          option,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
