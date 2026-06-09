import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'intents.dart';

/// Single definition of every command accelerator.
///
/// The macOS menu items use the `meta`-based activators below as their
/// displayed `shortcut:`, and [appShortcuts] maps the same activators (plus
/// `control`-based equivalents for Windows/Linux and the no-menu fallback) to
/// the matching [Intent]. Defining each key combo once keeps the menu and the
/// keyboard shortcuts from drifting apart.

// ── macOS menu accelerators (also reused in [appShortcuts]) ─────────────────
const kReloadDevicesShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  meta: true,
  shift: true,
);
const kStartLogcatShortcut = SingleActivator(
  LogicalKeyboardKey.keyR,
  meta: true,
);
const kPauseResumeShortcut = SingleActivator(
  LogicalKeyboardKey.space,
  meta: true,
);
const kClearLogsShortcut = SingleActivator(LogicalKeyboardKey.keyK, meta: true);
const kScrollToEndShortcut = SingleActivator(
  LogicalKeyboardKey.end,
  meta: true,
);
const kFindShortcut = SingleActivator(LogicalKeyboardKey.keyF, meta: true);
const kPreviousMatchShortcut = SingleActivator(
  LogicalKeyboardKey.keyG,
  meta: true,
  shift: true,
);
const kNextMatchShortcut = SingleActivator(LogicalKeyboardKey.keyG, meta: true);
const kFocusFilterShortcut = SingleActivator(
  LogicalKeyboardKey.keyL,
  meta: true,
);
const kInstallAppShortcut = SingleActivator(
  LogicalKeyboardKey.keyI,
  meta: true,
  shift: true,
);
const kExportLogsShortcut = SingleActivator(
  LogicalKeyboardKey.keyS,
  meta: true,
  shift: true,
);
const kSettingsShortcut = SingleActivator(LogicalKeyboardKey.comma, meta: true);
const kQuitShortcut = SingleActivator(LogicalKeyboardKey.keyQ, meta: true);
const kIncreaseFontShortcut = SingleActivator(
  LogicalKeyboardKey.equal,
  meta: true,
);
const kDecreaseFontShortcut = SingleActivator(
  LogicalKeyboardKey.minus,
  meta: true,
);

/// The in-app keyboard shortcut table, wired to the same intents the menu uses.
/// Handles the keyboard path on every platform (and is the only path where
/// there is no native menu bar). The underlying command handlers guard
/// themselves, so a shortcut that fires while its menu item is disabled is a
/// harmless no-op.
const appShortcuts = <ShortcutActivator, Intent>{
  // Devices / app
  kReloadDevicesShortcut: ReloadDevicesIntent(),
  SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true):
      ReloadDevicesIntent(),
  kInstallAppShortcut: InstallAppIntent(),
  SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true):
      InstallAppIntent(),
  kExportLogsShortcut: ExportLogsIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
      ExportLogsIntent(),
  kSettingsShortcut: OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.comma, control: true):
      OpenSettingsIntent(),

  // Capture
  kStartLogcatShortcut: StartLogcatIntent(),
  SingleActivator(LogicalKeyboardKey.keyR, control: true): StartLogcatIntent(),
  kPauseResumeShortcut: TogglePauseResumeIntent(),
  SingleActivator(LogicalKeyboardKey.space, control: true):
      TogglePauseResumeIntent(),
  kClearLogsShortcut: ClearLogsIntent(),
  SingleActivator(LogicalKeyboardKey.keyK, control: true): ClearLogsIntent(),
  kScrollToEndShortcut: ScrollToEndIntent(),
  SingleActivator(LogicalKeyboardKey.end, control: true): ScrollToEndIntent(),

  // Search
  kFindShortcut: ActivateSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, control: true):
      ActivateSearchIntent(),
  kNextMatchShortcut: NextMatchIntent(),
  SingleActivator(LogicalKeyboardKey.keyG, control: true): NextMatchIntent(),
  kPreviousMatchShortcut: PreviousMatchIntent(),
  SingleActivator(LogicalKeyboardKey.keyG, control: true, shift: true):
      PreviousMatchIntent(),

  // Filter
  kFocusFilterShortcut: FocusFilterIntent(),
  SingleActivator(LogicalKeyboardKey.keyL, control: true): FocusFilterIntent(),

  // View — font size
  kIncreaseFontShortcut: IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.equal, control: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
      IncreaseFontIntent(),
  kDecreaseFontShortcut: DecreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.minus, control: true):
      DecreaseFontIntent(),
};
