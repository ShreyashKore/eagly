import 'package:flutter/material.dart';

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
              decoration: const InputDecoration(
                hintText: 'Filter logs...',
                prefixIcon: Icon(Icons.filter_alt_outlined),
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
              items: const [
                DropdownMenuItem(value: 'E', child: Text('Error (E)')),
                DropdownMenuItem(value: 'W', child: Text('Warning (W)')),
                DropdownMenuItem(value: 'I', child: Text('Info (I)')),
                DropdownMenuItem(value: 'D', child: Text('Debug (D)')),
                DropdownMenuItem(value: 'V', child: Text('Verbose (V)')),
              ],
              onChanged: onLogLevelChanged,
            ),
          ),
        ],
      ),
    );
  }
}
