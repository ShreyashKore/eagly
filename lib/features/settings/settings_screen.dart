import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/app_icon_button.dart';
import '../emulator_manager/services/android_sdk_picker.dart';
import '../logs/data/models/log_level.dart';
import '../mirror/services/capture_storage.dart';
import '../../utils/file_reveal.dart';
import '../../services/eagly_info_service.dart';
import '../../services/preferences_service.dart';
import '../../presentation/components/app_log_overlay.dart';
import '../../presentation/components/eagly_dialog.dart';
import '../../presentation/theme/app_theme.dart';
import '../../utils/android_sdk_path.dart';
import 'components/settings_section_card.dart';
import '../../presentation/components/snack_bars.dart';

/// Presents the settings as a large desktop dialog.
Future<void> showSettingsDialog(BuildContext context) {
  return showEaglyDialog<void>(
    context: context,
    builder: (_) => const SettingsScreen(),
  );
}

class const SettingsScreen({super.key}) extends StatefulWidget {
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themePreference;
  late bool _wrapText;
  late bool _autoScroll;
  late LogLevel _selectedLogLevel;
  late double _logFontSize;
  late double _zoomLevel;
  late bool _tipsEnabled;
  late String _captureDirectory;
  late bool _captureAskEveryTime;
  late bool _rememberHiddenColumns;
  late AndroidSdkLocation _androidSdk;
  late final TextEditingController _logLinesController;

  @override
  void initState() {
    super.initState();
    _themePreference = PreferencesService.themeMode;
    _wrapText = PreferencesService.wrapText;
    _autoScroll = PreferencesService.autoScroll;
    _selectedLogLevel = PreferencesService.selectedLogLevel;
    _logFontSize = PreferencesService.logFontSize;
    _zoomLevel = PreferencesService.zoomLevel;
    _tipsEnabled = PreferencesService.tipsEnabled;
    _captureDirectory = CaptureStorage.resolveDirectory();
    _captureAskEveryTime = PreferencesService.captureAskEveryTime;
    _rememberHiddenColumns = PreferencesService.rememberHiddenColumns;
    _androidSdk = AndroidSdkPath.locate();
    _logLinesController = TextEditingController(
      text: PreferencesService.logLinesLimit.toString(),
    );
  }

  @override
  void dispose() {
    _logLinesController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) => showMessageSnackBar(context, message);

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

  Future<void> _chooseCaptureDirectory() async {
    final chosen = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder for screenshots and recordings',
      // The Windows picker throws on a folder that has since been deleted.
      initialDirectory: Directory(_captureDirectory).existsSync()
          ? _captureDirectory
          : null,
    );
    if (chosen == null || chosen.trim().isEmpty) return;
    await PreferencesService.setCaptureDirectory(chosen);
    if (!mounted) return;
    setState(() => _captureDirectory = CaptureStorage.resolveDirectory());
    _showSnackBar('Captures will be saved to $chosen.');
  }

  Future<void> _resetCaptureDirectory() async {
    await PreferencesService.setCaptureDirectory(null);
    if (!mounted) return;
    setState(() => _captureDirectory = CaptureStorage.resolveDirectory());
    _showSnackBar('Capture folder reset to the default.');
  }

  Future<void> _openCaptureDirectory() async {
    await CaptureStorage.ensureDirectory();
    await openPathExternally(_captureDirectory);
  }

  Future<void> _chooseAndroidSdk() async {
    final choice = await AndroidSdkPicker.chooseAndSave(
      initialDirectory: _androidSdk.sdkPath,
    );
    if (choice == null || !mounted) return;

    setState(() => _androidSdk = AndroidSdkPath.locate());
    _showSnackBar(choice.message);
  }

  Future<void> _resetAndroidSdk() async {
    await AndroidSdkPicker.clear();
    if (!mounted) return;
    setState(() => _androidSdk = AndroidSdkPath.locate());
    _showSnackBar('Android SDK location reset to the default.');
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

  /// Both halves of the question: which SDK (the path, in [pathStyle]), and
  /// whether it can actually launch anything. `adb` is bundled and always
  /// works, so the emulator is the only reason this setting exists.
  InlineSpan _androidSdkSummary(TextStyle pathStyle) {
    final path = _androidSdk.sdkPath;
    final status = switch (_androidSdk.status) {
      AndroidSdkStatus.ready => 'Emulator ready',
      AndroidSdkStatus.emulatorMissing => 'No emulator package in this SDK',
      AndroidSdkStatus.sdkMissing =>
        'Not found — choose the folder that contains platform-tools '
            'and emulator',
    };
    if (path == null || _androidSdk.status == AndroidSdkStatus.sdkMissing) {
      return TextSpan(text: status);
    }
    return TextSpan(
      children: [
        TextSpan(text: path, style: pathStyle),
        TextSpan(text: '\n$status'),
      ],
    );
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
    // Folder paths read as values to copy or compare, not prose.
    final pathStyle = context.eaglyTheme.monoStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      height: 1.4,
    );
    return EaglyDialog(
      title: 'Settings',
      icon: Icons.settings_outlined,
      width: 820,
      height: 640,
      contentPadding: EdgeInsets.zero,
      // Every row is a title over an explanation or its current value; the
      // default subtitle color (onSurfaceVariant) is barely lighter than the
      // title in the light theme, so set it to secondary text here.
      child: ListTileTheme.merge(
        subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: context.eaglyTheme.secondaryTextColor,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            SettingsSectionCard(
              title: 'Appearance',
              children: [
                SettingsRow(
                  child: Row(
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
                ),
                SettingsRow(
                  child: Row(
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
                ),
                SettingsRow(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Zoom level',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 12,
                        children: [
                          AppIconButton(
                            icon: Icons.zoom_out,
                            onPressed: () {
                              final next = (PreferencesService.zoomLevel - 0.05)
                                  .clamp(0.7, 1.8);
                              setState(() => _zoomLevel = next);
                              PreferencesService.zoomLevel = next;
                            },
                          ),
                          SizedBox(
                            width: 200,
                            child: Slider(
                              value: _zoomLevel,
                              min: 0.7,
                              max: 1.8,
                              divisions: 22,
                              label:
                                  '${(_zoomLevel * 100).toStringAsFixed(0)}%',
                              onChanged: (v) {
                                setState(() => _zoomLevel = v);
                                PreferencesService.zoomLevel = v;
                              },
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.zoom_in,
                            onPressed: () {
                              final next = (PreferencesService.zoomLevel + 0.05)
                                  .clamp(0.7, 1.8);
                              setState(() => _zoomLevel = next);
                              PreferencesService.zoomLevel = next;
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  value: _tipsEnabled,
                  title: const Text('Feature tips'),
                  subtitle: const Text('Show a rotating tip in the app header'),
                  onChanged: (value) {
                    setState(() => _tipsEnabled = value);
                    PreferencesService.tipsEnabled = value;
                  },
                ),
              ],
            ),
            const Gap(16),
            SettingsSectionCard(
              title: 'Defaults for new tabs',
              children: [
                SwitchListTile(
                  dense: true,
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
                  title: const Text('Default log level'),
                  trailing: SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<LogLevel>(
                      initialValue: _selectedLogLevel,
                      isExpanded: true,
                      items: LogLevel.values
                          .map(
                            (level) => DropdownMenuItem<LogLevel>(
                              value: level,
                              child: Text(level.labelWithCode),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedLogLevel = value);
                        PreferencesService.selectedLogLevel = value;
                      },
                    ),
                  ),
                ),
                // (no explicit Divider here)
                SettingsRow(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Max log lines'),
                            Text(
                              'Minimum 1000',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: context.eaglyTheme.tertiaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Sized for the number it holds — seven digits — not
                      // for whatever the row has left over.
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _logLinesController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                '${PreferencesService.defaultLogLinesLimit}',
                          ),
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
                ),
              ],
            ),
            const Gap(16),
            SettingsSectionCard(
              title: 'Screenshots & recordings',
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Save folder'),
                  subtitle: Tooltip(
                    message: _captureDirectory,
                    child: Text(
                      _captureDirectory,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: pathStyle,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        tooltip: 'Open folder',
                        icon: Icons.folder_open_outlined,
                        onPressed: _openCaptureDirectory,
                      ),
                      TextButton(
                        onPressed: _chooseCaptureDirectory,
                        child: const Text('Change…'),
                      ),
                      TextButton(
                        onPressed: PreferencesService.captureDirectory == null
                            ? null
                            : _resetCaptureDirectory,
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  value: _captureAskEveryTime,
                  title: const Text('Ask where to save each time'),
                  subtitle: const Text(
                    'Show a save dialog instead of using the folder above',
                  ),
                  onChanged: (value) {
                    setState(() => _captureAskEveryTime = value);
                    PreferencesService.captureAskEveryTime = value;
                  },
                ),
              ],
            ),
            const Gap(16),
            SettingsSectionCard(
              title: 'Android SDK',
              children: [
                ListTile(
                  dense: true,
                  title: const Text('SDK location'),
                  subtitle: Tooltip(
                    message: _androidSdk.sdkPath ?? '',
                    child: Text.rich(
                      _androidSdkSummary(pathStyle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _androidSdk.isReady
                            ? null
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _chooseAndroidSdk,
                        child: const Text('Change…'),
                      ),
                      TextButton(
                        onPressed: PreferencesService.androidSdkPath == null
                            ? null
                            : _resetAndroidSdk,
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(16),
            SettingsSectionCard(
              title: 'Stored layout defaults',
              children: [
                SwitchListTile(
                  dense: true,
                  value: _rememberHiddenColumns,
                  title: const Text('Remember hidden columns'),
                  subtitle: const Text(
                    'Columns shown or hidden in a log tab become the default '
                    'for new tabs',
                  ),
                  onChanged: (value) {
                    setState(() => _rememberHiddenColumns = value);
                    PreferencesService.rememberHiddenColumns = value;
                  },
                ),
                ListTile(
                  dense: true,
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
            SettingsSectionCard(
              title: 'About',
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Version'),
                  trailing: Text(EaglyInfoService.appVersion),
                ),
                ListTile(
                  dense: true,
                  title: const Text('App logs'),
                  subtitle: const Text(
                    'Open the internal debugging log viewer and copy full app logs.',
                  ),
                  onTap: () => showAppLogDialog(title: 'App Logs', context),
                  trailing: const AppLogTriggerButton(
                    title: 'App Logs',
                    tooltip: 'Show app logs',
                    iconSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
