import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';

class FilterBar extends StatelessWidget {
  final String filterQuery;
  final ValueChanged<String> onFilterChanged;
  final String selectedLogLevel;
  final ValueChanged<String?> onLogLevelChanged;

  const FilterBar({
    super.key,
    required this.filterQuery,
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
            child: !Platform.isAndroid
                ? CupertinoTextField(
                    placeholder: 'Filter logs...',
                    onChanged: onFilterChanged,
                  )
                : TextField(
                    decoration: const InputDecoration(
                      hintText: 'Filter logs...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: onFilterChanged,
                  ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
                  isDense: true,
                  mouseCursor: SystemMouseCursors.click,
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  value: selectedLogLevel,
                  items: const [
                    DropdownMenuItem(value: 'E', child: Text('Error (E)')),
                    DropdownMenuItem(value: 'W', child: Text('Warning (W)')),
                    DropdownMenuItem(value: 'I', child: Text('Info (I)')),
                    DropdownMenuItem(value: 'D', child: Text('Debug (D)')),
                    DropdownMenuItem(value: 'V', child: Text('Verbose (V)')),
                  ],
                  onChanged: onLogLevelChanged,
                ),
        ],
      ),
    );
  }
}
