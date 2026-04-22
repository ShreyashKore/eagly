import 'package:flutter/material.dart';
import 'package:logview/theme/app_theme.dart';

import 'data/log_view_mode.dart';
import 'services/app_info_service.dart';
import 'services/preferences_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themePreference;
  late bool _wrapText;
  late bool _autoScroll;
  late String _selectedLogLevel;
  late LogViewMode _viewMode;
  late final TextEditingController _logLinesController;

  @override
  void initState() {
    super.initState();
    _themePreference = PreferencesService.themeMode;
    _wrapText = PreferencesService.wrapText;
    _autoScroll = PreferencesService.autoScroll;
    _selectedLogLevel = PreferencesService.selectedLogLevel;
    _viewMode = PreferencesService.viewMode;
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Switch between auto, light, and dark theme modes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: const Text('Theme mode'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<ThemeMode>(
                        initialValue: _themePreference,
                        isExpanded: true,
                        items: ThemeMode.values
                            .map(
                              (preference) => DropdownMenuItem(
                                value: preference,
                                child: Text(preference.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _themePreference = value);
                          PreferencesService.themeMode = value;
                        },
                        decoration: InputDecoration(
                          helperText: _themePreference.description,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Defaults for new tabs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Open tabs keep their local configuration in memory. These values are used only when a new tab is created.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _wrapText,
                      title: const Text('Wrap text'),
                      subtitle: const Text(
                        'Controls the message column wrapping.',
                      ),
                      onChanged: (value) {
                        setState(() => _wrapText = value);
                        PreferencesService.wrapText = value;
                      },
                    ),
                    SwitchListTile(
                      value: _autoScroll,
                      title: const Text('Auto-scroll'),
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
                          DropdownMenuItem(
                            value: 'E',
                            child: Text('Error (E)'),
                          ),
                          DropdownMenuItem(
                            value: 'W',
                            child: Text('Warning (W)'),
                          ),
                          DropdownMenuItem(value: 'I', child: Text('Info (I)')),
                          DropdownMenuItem(
                            value: 'D',
                            child: Text('Debug (D)'),
                          ),
                          DropdownMenuItem(
                            value: 'V',
                            child: Text('Verbose (V)'),
                          ),
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
                          PreferencesService.viewMode = value;
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Max log lines kept in memory'),
                      subtitle: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                'Stored layout defaults',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Default hidden columns'),
                      subtitle: Text(
                        '${hiddenColumns.length} columns hidden for newly created tabs',
                      ),
                      trailing: TextButton(
                        onPressed: hiddenColumns.isEmpty
                            ? null
                            : _resetHiddenColumns,
                        child: const Text('Reset'),
                      ),
                    ),
                    ListTile(
                      title: const Text('Default column widths'),
                      subtitle: const Text(
                        'Reset the persisted widths used when new tabs are created.',
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
        ),
      ),
    );
  }
}
