import 'package:flutter/material.dart';

import '../constants/log_constants.dart';

class FilterBar extends StatelessWidget {
  final String filterQuery;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onFilterChanged;
  final String selectedLogLevel;
  final ValueChanged<String?> onLogLevelChanged;

  const FilterBar({
    super.key,
    required this.filterQuery,
    this.controller,
    this.focusNode,
    required this.onFilterChanged,
    required this.selectedLogLevel,
    required this.onLogLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Filter logs...',
                prefixIconConstraints: BoxConstraints(
                  minHeight: 32,
                  minWidth: 32,
                ),
                prefixIcon: Icon(Icons.filter_alt_outlined, size: 20),
              ),
              onChanged: onFilterChanged,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: selectedLogLevel,
              decoration: const InputDecoration(labelText: 'Level'),
              items: buildLogLevelDropdownItems(includeValueInLabel: true),
              onChanged: onLogLevelChanged,
            ),
          ),
        ],
      ),
    );
  }
}
