import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../constants/log_constants.dart';
import '../../services/app_info_service.dart';
import '../../services/preferences_service.dart';

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
  late double _logFontSize;
  late final TextEditingController _logLinesController;

  @override
  void initState() {
    super.initState();
    _themePreference = PreferencesService.themeMode;
    _wrapText = PreferencesService.wrapText;
    _autoScroll = PreferencesService.autoScroll;
    _selectedLogLevel = PreferencesService.selectedLogLevel;
    _logFontSize = PreferencesService.logFontSize;
    _logLinesController = TextEditingController(
      text: PreferencesService.logLinesLimit.toString(),
    );
  }

  @override
  void dispose() {
    _logLinesController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveLogLinesLimit() async {
    final parsed = int.tryParse(_logLinesController.text.trim());
    if (parsed == null || parsed < 1000) {
      _showSnackBar('Max lines must be at least 1000.');
      return;
    }

    setState(() {
      _logLinesController.text = parsed.toString();
    });
    PreferencesService.logLinesLimit = parsed;
    _showSnackBar('Max lines updated.');
  }

  Future<void> _resetHiddenColumns() async {
    PreferencesService.hiddenColumns = {};
    if (!mounted) return;
    setState(() {});
    _showSnackBar('Hidden columns reset.');
  }

  Future<void> _resetColumnWidths() async {
    PreferencesService.columnWidths = {};
    if (!mounted) return;
    setState(() {});
    _showSnackBar('Column widths reset.');
  }

  int get _themeIndex {
    switch (_themePreference) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
        return 0;
    }
  }

  void _setThemeByIndex(int index) {
    final mode = [ThemeMode.system, ThemeMode.light, ThemeMode.dark][index];
    setState(() => _themePreference = mode);
    PreferencesService.themeMode = mode;
  }

  @override
  Widget build(BuildContext context) {
    final hiddenColumns = PreferencesService.hiddenColumns;
    final theme = Theme.of(context);
    Widget sectionCard({
      required String title,
      required List<Widget> children,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: List<Widget>.generate(children.length * 2 - 1, (i) {
                  final index = i ~/ 2;
                  if (i.isEven) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: children[index],
                    );
                  }
                  return const Divider(height: 1);
                }),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              sectionCard(
                title: 'Appearance',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Theme', style: theme.textTheme.bodyLarge),
                      ),
                      ToggleButtons(
                        isSelected: List.generate(
                          3,
                          (i) => i == _themeIndex,
                          growable: false,
                        ),
                        onPressed: (index) => _setThemeByIndex(index),
                        borderRadius: BorderRadius.circular(6),
                        selectedBorderColor: theme.colorScheme.primary
                            .withValues(alpha: 0.5),
                        constraints: const BoxConstraints(
                          minWidth: 84,
                          minHeight: 36,
                        ),
                        children: const [
                          Text('Auto'),
                          Text('Light'),
                          Text('Dark'),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Log font size',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 12,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Aa',
                              style: TextStyle(fontSize: _logFontSize),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: Slider(
                              value: _logFontSize,
                              min: 8,
                              max: 24,
                              divisions: 16,
                              label: _logFontSize.toStringAsFixed(0),
                              onChanged: (v) {
                                setState(() => _logFontSize = v);
                                PreferencesService.logFontSize = v;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const Gap(16),
              sectionCard(
                title: 'Defaults for new tabs',
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _wrapText,
                    title: const Text('Wrap text'),
                    subtitle: const Text('Message column wraps'),
                    onChanged: (value) {
                      setState(() => _wrapText = value);
                      PreferencesService.wrapText = value;
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _autoScroll,
                    title: const Text('Auto-scroll'),
                    subtitle: const Text('Keep view pinned to latest'),
                    onChanged: (value) {
                      setState(() => _autoScroll = value);
                      PreferencesService.autoScroll = value;
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default log level'),
                    trailing: SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedLogLevel,
                        isExpanded: true,
                        items: buildLogLevelDropdownItems(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedLogLevel = value);
                          PreferencesService.selectedLogLevel = value;
                        },
                      ),
                    ),
                  ),
                  // (no explicit Divider here)
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Max log lines'),
                          Text(
                            'Minimum 1000',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      Gap(200),
                      Expanded(
                        child: TextField(
                          controller: _logLinesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '50000'),
                          onSubmitted: (_) => _saveLogLinesLimit(),
                        ),
                      ),
                      const Gap(12),
                      FilledButton(
                        onPressed: _saveLogLinesLimit,
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
              const Gap(16),
              sectionCard(
                title: 'Stored layout defaults',
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default hidden columns'),
                    subtitle: Text(
                      '${hiddenColumns.length} columns hidden by default',
                    ),
                    trailing: TextButton(
                      onPressed: hiddenColumns.isEmpty
                          ? null
                          : _resetHiddenColumns,
                      child: const Text('Reset'),
                    ),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default column widths'),
                    subtitle: const Text('Persisted widths for new tabs'),
                    trailing: TextButton(
                      onPressed: _resetColumnWidths,
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
              const Gap(16),
              sectionCard(
                title: 'About',
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Version'),
                    trailing: Text(AppInfoService.appVersion),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
