import 'package:flutter/widgets.dart';

import '../features/logs/data/models/log_level.dart';

/// App-wide command intents. Each user command (whether triggered from the
/// macOS menu bar via [PlatformMenuItem.onSelectedIntent] or from a keyboard
/// shortcut via the app [Shortcuts] map) is expressed as one of these intents
/// and handled by a single `Actions` map. This keeps "what a command does"
/// defined in exactly one place.

// ── App / window ────────────────────────────────────────────────────────────
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class ShowAboutIntent extends Intent {
  const ShowAboutIntent();
}

class QuitAppIntent extends Intent {
  const QuitAppIntent();
}

class ReloadDevicesIntent extends Intent {
  const ReloadDevicesIntent();
}

class InstallAppIntent extends Intent {
  const InstallAppIntent();
}

class ExportLogsIntent extends Intent {
  const ExportLogsIntent();
}

class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

// ── Capture ──────────────────────────────────────────────────────────────────
class StartLogcatIntent extends Intent {
  const StartLogcatIntent();
}

class TogglePauseResumeIntent extends Intent {
  const TogglePauseResumeIntent();
}

class ClearLogsIntent extends Intent {
  const ClearLogsIntent();
}

class ScrollToEndIntent extends Intent {
  const ScrollToEndIntent();
}

// ── Search ────────────────────────────────────────────────────────────────────
class ActivateSearchIntent extends Intent {
  const ActivateSearchIntent();
}

class NextMatchIntent extends Intent {
  const NextMatchIntent();
}

class PreviousMatchIntent extends Intent {
  const PreviousMatchIntent();
}

// ── Filter ────────────────────────────────────────────────────────────────────
class FocusFilterIntent extends Intent {
  const FocusFilterIntent();
}

class ClearFilterIntent extends Intent {
  const ClearFilterIntent();
}

class SetLogLevelIntent extends Intent {
  const SetLogLevelIntent(this.level);

  final LogLevel level;
}

// ── View ──────────────────────────────────────────────────────────────────────
class ToggleWrapTextIntent extends Intent {
  const ToggleWrapTextIntent();
}

class ToggleAutoScrollIntent extends Intent {
  const ToggleAutoScrollIntent();
}

class IncreaseFontIntent extends Intent {
  const IncreaseFontIntent();
}

class DecreaseFontIntent extends Intent {
  const DecreaseFontIntent();
}
