import 'package:flutter/material.dart';

import 'services/app_info_service.dart';
import 'services/preferences_service.dart';
import 'widgets/action_toolbar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _wrapText;
  late bool _autoScroll;
  late String _selectedLogLevel;
  late LogViewMode _viewMode;
  late final TextEditingController _logLinesController;

  @override
  void initState() {
    super.initState();
    _wrapText = PreferencesService.wrapText;
    _autoScroll = PreferencesService.autoScroll;
    _selectedLogLevel = PreferencesService.selectedLogLevel;
    _viewMode =
        LogViewMode.values[PreferencesService.viewMode.clamp(
          0,
          LogViewMode.values.length - 1,
        )];
    _logLinesController = TextEditingController(
      text: PreferencesService.logLinesLimit.toString(),
    );
  }

  @override
  void dispose() {
    _logLinesController.dispose();
    super.dispose();
  }

  String _viewModeLabel(LogViewMode mode) {
    return switch (mode) {
      LogViewMode.text => 'Text',
      LogViewMode.dataTable => 'Data Table',
      LogViewMode.worksheet => 'Worksheet',
    };
  }

  Future<void> _saveLogLinesLimit() async {
    final parsed = int.tryParse(_logLinesController.text.trim());
    if (parsed == null || parsed < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max lines must be at least 1000.')),
      );
      return;
    }

    setState(() {
      _logLinesController.text = parsed.toString();
    });
    PreferencesService.logLinesLimit = parsed;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Max lines updated.')));
  }

  Future<void> _resetHiddenColumns() async {
    PreferencesService.hiddenColumns = {};
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Hidden columns reset.')));
  }

  Future<void> _resetColumnWidths() async {
    PreferencesService.columnWidths = {};
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Column widths reset.')));
  }

  @override
  Widget build(BuildContext context) {
    final hiddenColumns = PreferencesService.hiddenColumns;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('General', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _wrapText,
                  title: const Text('Wrap text by default'),
                  subtitle: const Text('Controls the message column wrapping.'),
                  onChanged: (value) {
                    setState(() => _wrapText = value);
                    PreferencesService.wrapText = value;
                  },
                ),
                SwitchListTile.adaptive(
                  value: _autoScroll,
                  title: const Text('Auto-scroll by default'),
                  subtitle: const Text(
                    'Keep the view pinned to the latest logs.',
                  ),
                  onChanged: (value) {
                    setState(() => _autoScroll = value);
                    PreferencesService.autoScroll = value;
                  },
                ),
                ListTile(
                  title: const Text('Default log level filter'),
                  subtitle: DropdownButtonFormField<String>(
                    initialValue: _selectedLogLevel,
                    items: const [
                      DropdownMenuItem(value: 'E', child: Text('Error (E)')),
                      DropdownMenuItem(value: 'W', child: Text('Warning (W)')),
                      DropdownMenuItem(value: 'I', child: Text('Info (I)')),
                      DropdownMenuItem(value: 'D', child: Text('Debug (D)')),
                      DropdownMenuItem(value: 'V', child: Text('Verbose (V)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedLogLevel = value);
                      PreferencesService.selectedLogLevel = value;
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Default view mode'),
                  subtitle: DropdownButtonFormField<LogViewMode>(
                    initialValue: _viewMode,
                    items: LogViewMode.values
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(_viewModeLabel(mode)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _viewMode = value);
                      PreferencesService.viewMode = value.index;
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Max log lines kept in memory'),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _logLinesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '50000',
                            helperText: 'Minimum: 1000',
                          ),
                          onSubmitted: (_) => _saveLogLinesLimit(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saveLogLinesLimit,
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Layout', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Hidden columns'),
                  subtitle: Text('${hiddenColumns.length} columns hidden'),
                  trailing: TextButton(
                    onPressed: hiddenColumns.isEmpty
                        ? null
                        : _resetHiddenColumns,
                    child: const Text('Reset'),
                  ),
                ),
                ListTile(
                  title: const Text('Stored column widths'),
                  subtitle: const Text(
                    'Reset the persisted widths for all columns.',
                  ),
                  trailing: TextButton(
                    onPressed: _resetColumnWidths,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Version'),
              subtitle: Text(AppInfoService.appVersion),
            ),
          ),
        ],
      ),
    );
  }
}
