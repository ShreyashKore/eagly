import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'intents.dart';
import '../features/logs/data/models/log_level.dart';
import 'app_menu_scope.dart';
import 'shortcuts.dart';
import 'app_menu_state.dart';

/// The macOS menu bar, rebuilt from the reactive [AppMenuState] in
/// [AppMenuScope]. It is purely declarative: every item dispatches an [Intent]
/// (handled by the app-level `Actions`) and derives its enabled state and label
/// from the snapshot. It holds no controllers or callbacks of its own.
///
/// Because it only depends on the snapshot, it rebuilds when — and only when —
/// the snapshot changes, so an open native menu is not torn down by unrelated
/// app activity.
class AppPlatformMenuBar extends StatelessWidget {
  const AppPlatformMenuBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = AppMenuScope.stateOf(context);
    return PlatformMenuBar(menus: _menus(state), child: child);
  }

  /// An item that is enabled only when [enabled] is true (disabled items get a
  /// null intent, which is how [PlatformMenuItem] renders them greyed out).
  PlatformMenuItem _item(
    String label,
    Intent intent, {
    bool enabled = true,
    MenuSerializableShortcut? shortcut,
  }) {
    return PlatformMenuItem(
      label: label,
      shortcut: shortcut,
      onSelectedIntent: enabled ? intent : null,
    );
  }

  List<PlatformMenuItem> _menus(AppMenuState s) {
    return [
      // ── File ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item(
                'Install App on Selected Device…',
                const InstallAppIntent(),
                enabled: s.canInstallApp,
                shortcut: kInstallAppShortcut,
              ),
              _item(
                'Export Logs…',
                const ExportLogsIntent(),
                enabled: s.canExport,
                shortcut: kExportLogsShortcut,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item(
                'Settings…',
                const OpenSettingsIntent(),
                shortcut: kSettingsShortcut,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item(
                'Quit ${AppConstants.appName}',
                const QuitAppIntent(),
                shortcut: kQuitShortcut,
              ),
            ],
          ),
        ],
      ),

      // ── Logs ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Logs',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item(
                'Reload Devices',
                const ReloadDevicesIntent(),
                shortcut: kReloadDevicesShortcut,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item(
                s.isRunning ? 'Restart Capture' : 'Start Capture',
                const StartLogcatIntent(),
                enabled: s.canCapture,
                shortcut: kStartLogcatShortcut,
              ),
              _item(
                s.isPaused ? 'Resume Capture' : 'Pause Capture',
                const TogglePauseResumeIntent(),
                enabled: s.canPauseResume,
                shortcut: kPauseResumeShortcut,
              ),
              _item(
                'Clear Logs',
                const ClearLogsIntent(),
                enabled: s.canClear,
                shortcut: kClearLogsShortcut,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item(
                'Scroll to End',
                const ScrollToEndIntent(),
                enabled: s.canInteractWithLog,
                shortcut: kScrollToEndShortcut,
              ),
            ],
          ),
        ],
      ),

      // ── Search ────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Search',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item(
                'Find…',
                const ActivateSearchIntent(),
                enabled: s.canInteractWithLog,
                shortcut: kFindShortcut,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item(
                'Previous Match',
                const PreviousMatchIntent(),
                enabled: s.canInteractWithLog,
                shortcut: kPreviousMatchShortcut,
              ),
              _item(
                'Next Match',
                const NextMatchIntent(),
                enabled: s.canInteractWithLog,
                shortcut: kNextMatchShortcut,
              ),
            ],
          ),
        ],
      ),

      // ── Filter ────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Filter',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item(
                'Focus Filter Input',
                const FocusFilterIntent(),
                enabled: s.canInteractWithLog,
                shortcut: kFocusFilterShortcut,
              ),
              _item(
                'Clear Filter',
                const ClearFilterIntent(),
                enabled: s.canInteractWithLog,
              ),
            ],
          ),
          PlatformMenuItemGroup(members: _logLevelItems(s)),
        ],
      ),

      // ── View ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item(
                _checked(s.wrapText, 'Wrap Text'),
                const ToggleWrapTextIntent(),
                enabled: s.canInteractWithLog,
              ),
              _item(
                _checked(s.autoScroll, 'Auto-scroll'),
                const ToggleAutoScrollIntent(),
                enabled: s.canInteractWithLog,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
               _item(
                 'Zoom In',
                 const IncreaseFontIntent(),
                 shortcut: kIncreaseFontShortcut,
               ),
               _item(
                 'Zoom Out',
                 const DecreaseFontIntent(),
                 shortcut: kDecreaseFontShortcut,
               ),
            ],
          ),
        ],
      ),

      // ── Help ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item('About ${AppConstants.appName}', const ShowAboutIntent()),
            ],
          ),
        ],
      ),
    ];
  }

  /// macOS menu items have no native checkmark in Flutter's API, so a selected
  /// toggle is shown with a leading check glyph.
  String _checked(bool on, String label) => on ? '✓ $label' : label;

  List<PlatformMenuItem> _logLevelItems(AppMenuState s) {
    final levels = s.isIos ? LogLevel.iosValues : LogLevel.androidValues;
    return [
      for (final level in levels)
        _item(
          _checked(
            level == s.selectedLogLevel,
            level.labelWithDisplayCode(isIos: s.isIos),
          ),
          SetLogLevelIntent(level),
          enabled: s.canInteractWithLog,
        ),
    ];
  }
}
