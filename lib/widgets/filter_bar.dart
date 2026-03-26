import 'package:flutter/material.dart';

class FilterBar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String selectedLogLevel;
  final ValueChanged<String?> onLogLevelChanged;

  const FilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
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
              decoration: const InputDecoration(
                hintText: 'Search logs...',
                border: OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
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
