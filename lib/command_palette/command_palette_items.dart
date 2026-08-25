import 'dart:async';

import 'package:flutter/material.dart';

import '../app_menu/app_menu_controller.dart';
import '../app_menu/shortcuts.dart';
import '../constants/app_constants.dart';
import '../data/device.dart';
import '../features/logs/data/models/log_level.dart';
import '../features/utilities/data/utility_catalog.dart';
import '../features/utilities/utility_runner.dart';
import '../session/device_session_manager.dart';
import 'command_palette_item.dart';
import 'shortcut_label.dart';

/// Assembles the full, current set of palette entries.
///
/// Pulled together from every command source Eagly already has: app-chrome
/// actions (via the [onOpenSettings]-style callbacks, which mirror the
/// [Intent]s `home_page.dart` wires up), the active log's capture/search/
/// filter/view commands (via [menuController], the same source the desktop
/// menu bar reads), navigation across the *currently selected* device's
/// feature panes plus other connected devices (via [manager]), and that
/// device's Utilities catalog. Called fresh whenever [manager]/
/// [menuController] change, so the result stays contextual to whatever
/// device is selected while the palette is open.
///
/// [context] is only used to drive the Utilities params/confirmation dialogs
/// when a utility is run from here — pass a context that outlives the
/// palette dialog itself (e.g. the host screen's own `State.context`), not
/// one scoped to the palette, since selecting an item closes the palette
/// before [CommandPaletteItem.run] fires.
List<CommandPaletteItem> buildCommandPaletteItems({
  required BuildContext context,
  required DeviceSessionManager manager,
  required AppMenuController menuController,
  required VoidCallback onOpenSettings,
  required VoidCallback onShowAbout,
  required VoidCallback onQuit,
  required VoidCallback onInstallApp,
  required VoidCallback onExportLogs,
  required VoidCallback onShowWireless,
  required VoidCallback onImportLog,
  required VoidCallback onZoomIn,
  required VoidCallback onZoomOut,
  required void Function(String message) onShowSnackBar,
}) {
  final s = menuController.state;
  final session = manager.selected;
  final items = <CommandPaletteItem>[];

  // ── Navigate (currently selected device) ─────────────────────────────────
  if (session != null) {
    final deviceName = session.device.displayName;
    items.add(
      CommandPaletteItem(
        id: 'nav.home',
        label: 'Device Home',
        category: 'Navigate',
        icon: Icons.home_outlined,
        subtitle: deviceName,
        run: session.toggleHome,
      ),
    );
    items.add(
      CommandPaletteItem(
        id: 'nav.logs',
        label: 'Logs',
        category: 'Navigate',
        icon: Icons.article_outlined,
        subtitle: deviceName,
        run: session.toggleLogs,
      ),
    );
    if (session.canMirror || session.isMirrorOpen) {
      items.add(
        CommandPaletteItem(
          id: 'nav.mirror',
          label: 'Mirror',
          category: 'Navigate',
          icon: Icons.mobile_screen_share,
          subtitle: deviceName,
          run: session.toggleMirror,
        ),
      );
    }
    if (session.canReadCrashReports) {
      items.add(
        CommandPaletteItem(
          id: 'nav.crashes',
          label: 'Crash Reports',
          category: 'Navigate',
          icon: Icons.bug_report_outlined,
          subtitle: deviceName,
          run: session.toggleCrashReports,
        ),
      );
    }
    if (session.canManageFiles || session.isFilesOpen) {
      items.add(
        CommandPaletteItem(
          id: 'nav.files',
          label: 'File Manager',
          category: 'Navigate',
          icon: Icons.folder_outlined,
          subtitle: deviceName,
          run: session.toggleFiles,
        ),
      );
    }
    if (session.canManageApps || session.isAppsOpen) {
      items.add(
        CommandPaletteItem(
          id: 'nav.apps',
          label: 'Apps',
          category: 'Navigate',
          icon: Icons.apps_outlined,
          subtitle: deviceName,
          run: session.toggleApps,
        ),
      );
    }
    if (session.canUseTerminal) {
      items.add(
        CommandPaletteItem(
          id: 'nav.terminal',
          label: 'Terminal',
          category: 'Navigate',
          icon: Icons.terminal_outlined,
          subtitle: deviceName,
          run: session.toggleTerminal,
        ),
      );
      items.add(
        CommandPaletteItem(
          id: 'terminal.new-tab',
          label: 'New Terminal Tab',
          category: 'Navigate',
          icon: Icons.add_box_outlined,
          subtitle: deviceName,
          run: () {
            session.openTerminal();
            session.terminalSessionManager.addTab();
          },
        ),
      );
    }
    if (session.canRunUtilities) {
      items.add(
        CommandPaletteItem(
          id: 'nav.utilities',
          label: 'Utilities',
          category: 'Navigate',
          icon: Icons.handyman_outlined,
          subtitle: deviceName,
          run: session.toggleUtilities,
        ),
      );

      // Every utility this device's platform supports, straight from the
      // same catalog the Utilities pane reads — adding a command there
      // surfaces it here for free. Running one opens the pane (so its
      // params/confirmation dialog and result panel are visible) and goes
      // through the same runner the pane's own tiles use.
      for (final group in utilityCatalog) {
        for (final command in group.commands) {
          if (!command.supports(session.device)) continue;
          items.add(
            CommandPaletteItem(
              id: 'utility.${group.id}.${command.id}',
              label: command.label,
              category: 'Utilities',
              icon: command.icon,
              subtitle: command.previewFor(session.device),
              keywords: [group.title],
              run: () {
                session.openUtilities();
                unawaited(
                  runUtilityCommand(
                    context,
                    controller: session.utilitiesController,
                    command: command,
                    showSnackBar: onShowSnackBar,
                  ),
                );
              },
            ),
          );
        }
      }
    }
  }

  // ── Devices ───────────────────────────────────────────────────────────────
  if (!manager.isHome) {
    items.add(
      CommandPaletteItem(
        id: 'device.home-screen',
        label: 'Go to Home Screen',
        category: 'Devices',
        icon: Icons.dashboard_outlined,
        run: manager.goHome,
      ),
    );
  }
  for (final other in manager.sessions) {
    if (other.id == manager.selectedId) continue;
    items.add(
      CommandPaletteItem(
        id: 'device.switch.${other.id}',
        label: 'Switch to ${other.device.displayName}',
        category: 'Devices',
        icon: other.device is IosDevice
            ? Icons.phone_iphone
            : Icons.phone_android,
        subtitle: other.device.statusLabel,
        run: () => manager.select(other.id),
      ),
    );
  }

  // ── App ───────────────────────────────────────────────────────────────────
  items.add(
    CommandPaletteItem(
      id: 'app.reload-devices',
      label: 'Reload Devices',
      category: 'App',
      icon: Icons.refresh_rounded,
      shortcutLabel: describeShortcut(kReloadDevicesShortcut),
      run: menuController.reloadDevices,
    ),
  );
  if (s.canInstallApp) {
    items.add(
      CommandPaletteItem(
        id: 'app.install',
        label: 'Install App on Selected Device…',
        category: 'App',
        icon: Icons.system_update_outlined,
        shortcutLabel: describeShortcut(kInstallAppShortcut),
        run: onInstallApp,
      ),
    );
  }
  if (s.canExport) {
    items.add(
      CommandPaletteItem(
        id: 'app.export-logs',
        label: 'Export Logs…',
        category: 'App',
        icon: Icons.ios_share,
        shortcutLabel: describeShortcut(kExportLogsShortcut),
        run: onExportLogs,
      ),
    );
  }
  items.add(
    CommandPaletteItem(
      id: 'app.import-log',
      label: 'Import Log File…',
      category: 'App',
      icon: Icons.file_open_outlined,
      run: onImportLog,
    ),
  );
  items.add(
    CommandPaletteItem(
      id: 'app.wireless',
      label: 'Wireless ADB…',
      category: 'App',
      icon: Icons.wifi_tethering_outlined,
      run: onShowWireless,
    ),
  );
  items.add(
    CommandPaletteItem(
      id: 'app.settings',
      label: 'Settings…',
      category: 'App',
      icon: Icons.settings_rounded,
      shortcutLabel: describeShortcut(kSettingsShortcut),
      run: onOpenSettings,
    ),
  );
  items.add(
    CommandPaletteItem(
      id: 'app.about',
      label: 'About ${AppConstants.appName}',
      category: 'App',
      icon: Icons.info_outline,
      run: onShowAbout,
    ),
  );
  items.add(
    CommandPaletteItem(
      id: 'app.quit',
      label: 'Quit ${AppConstants.appName}',
      category: 'App',
      icon: Icons.exit_to_app,
      shortcutLabel: describeShortcut(kQuitShortcut),
      run: onQuit,
    ),
  );

  // ── Capture ───────────────────────────────────────────────────────────────
  if (s.canCapture) {
    items.add(
      CommandPaletteItem(
        id: 'capture.start',
        label: s.isRunning ? 'Restart Capture' : 'Start Capture',
        category: 'Capture',
        icon: Icons.fiber_manual_record_outlined,
        shortcutLabel: describeShortcut(kStartLogcatShortcut),
        run: menuController.startOrRestartLogcat,
      ),
    );
  }
  if (s.canPauseResume) {
    items.add(
      CommandPaletteItem(
        id: 'capture.pause-resume',
        label: s.isPaused ? 'Resume Capture' : 'Pause Capture',
        category: 'Capture',
        icon: s.isPaused ? Icons.play_arrow : Icons.pause,
        shortcutLabel: describeShortcut(kPauseResumeShortcut),
        run: menuController.togglePauseResume,
      ),
    );
  }
  if (s.canClear) {
    items.add(
      CommandPaletteItem(
        id: 'capture.clear',
        label: 'Clear Logs',
        category: 'Capture',
        icon: Icons.clear_all,
        shortcutLabel: describeShortcut(kClearLogsShortcut),
        run: menuController.clearLogs,
      ),
    );
  }
  if (s.canInteractWithLog) {
    items.add(
      CommandPaletteItem(
        id: 'capture.scroll-end',
        label: 'Scroll to End',
        category: 'Capture',
        icon: Icons.vertical_align_bottom,
        shortcutLabel: describeShortcut(kScrollToEndShortcut),
        run: menuController.scrollToEnd,
      ),
    );

    // ── Search ─────────────────────────────────────────────────────────────
    items.add(
      CommandPaletteItem(
        id: 'search.find',
        label: 'Find…',
        category: 'Search',
        icon: Icons.search,
        shortcutLabel: describeShortcut(kFindShortcut),
        run: menuController.activateSearch,
      ),
    );
    items.add(
      CommandPaletteItem(
        id: 'search.next',
        label: 'Next Match',
        category: 'Search',
        icon: Icons.arrow_downward,
        shortcutLabel: describeShortcut(kNextMatchShortcut),
        run: menuController.searchNext,
      ),
    );
    items.add(
      CommandPaletteItem(
        id: 'search.previous',
        label: 'Previous Match',
        category: 'Search',
        icon: Icons.arrow_upward,
        shortcutLabel: describeShortcut(kPreviousMatchShortcut),
        run: menuController.searchPrevious,
      ),
    );

    // ── Filter ─────────────────────────────────────────────────────────────
    items.add(
      CommandPaletteItem(
        id: 'filter.focus',
        label: 'Focus Filter Input',
        category: 'Filter',
        icon: Icons.filter_alt_outlined,
        shortcutLabel: describeShortcut(kFocusFilterShortcut),
        run: menuController.focusFilter,
      ),
    );
    items.add(
      CommandPaletteItem(
        id: 'filter.clear',
        label: 'Clear Filter',
        category: 'Filter',
        icon: Icons.filter_alt_off_outlined,
        run: menuController.clearFilter,
      ),
    );
    for (final level in s.isIos ? LogLevel.iosValues : LogLevel.androidValues) {
      items.add(
        CommandPaletteItem(
          id: 'filter.level.${level.code}',
          label: 'Log Level: ${level.labelWithDisplayCode(isIos: s.isIos)}',
          category: 'Filter',
          icon: Icons.dns_outlined,
          subtitle: level == s.selectedLogLevel ? 'Currently selected' : null,
          run: () => menuController.setLogLevel(level),
        ),
      );
    }

    // ── View ───────────────────────────────────────────────────────────────
    items.add(
      CommandPaletteItem(
        id: 'view.wrap-text',
        label: s.wrapText ? 'Disable Wrap Text' : 'Enable Wrap Text',
        category: 'View',
        icon: Icons.wrap_text,
        run: menuController.toggleWrapText,
      ),
    );
    items.add(
      CommandPaletteItem(
        id: 'view.auto-scroll',
        label: s.autoScroll ? 'Disable Auto-scroll' : 'Enable Auto-scroll',
        category: 'View',
        icon: Icons.low_priority,
        run: menuController.toggleAutoScroll,
      ),
    );
  }

  items.add(
    CommandPaletteItem(
      id: 'view.zoom-in',
      label: 'Zoom In',
      category: 'View',
      icon: Icons.zoom_in,
      shortcutLabel: describeShortcut(kIncreaseFontShortcut),
      run: onZoomIn,
    ),
  );
  items.add(
    CommandPaletteItem(
      id: 'view.zoom-out',
      label: 'Zoom Out',
      category: 'View',
      icon: Icons.zoom_out,
      shortcutLabel: describeShortcut(kDecreaseFontShortcut),
      run: onZoomOut,
    ),
  );

  return items;
}
