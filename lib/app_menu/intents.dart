import 'package:flutter/widgets.dart';

import '../features/logs/data/models/log_level.dart';

/// App-wide command intents. Each user command (whether triggered from the
/// macOS menu bar via [PlatformMenuItem.onSelectedIntent] or from a keyboard
/// shortcut via the app [Shortcuts] map) is expressed as one of these intents
/// and handled by a single `Actions` map. This keeps "what a command does"
/// defined in exactly one place.

// ── App / window ────────────────────────────────────────────────────────────
class const OpenSettingsIntent() extends Intent;

class const ShowAboutIntent() extends Intent;

class const QuitAppIntent() extends Intent;

class const ReloadDevicesIntent() extends Intent;

class const InstallAppIntent() extends Intent;

class const ExportLogsIntent() extends Intent;

class const OpenCommandPaletteIntent() extends Intent;

// ── Capture ──────────────────────────────────────────────────────────────────
class const StartLogcatIntent() extends Intent;

class const TogglePauseResumeIntent() extends Intent;

class const ClearLogsIntent() extends Intent;

class const ScrollToEndIntent() extends Intent;

// ── Search ────────────────────────────────────────────────────────────────────
class const ActivateSearchIntent() extends Intent;

class const NextMatchIntent() extends Intent;

class const PreviousMatchIntent() extends Intent;

// ── Filter ────────────────────────────────────────────────────────────────────
class const FocusFilterIntent() extends Intent;

class const ClearFilterIntent() extends Intent;

class const SetLogLevelIntent(this.level) extends Intent {
  final LogLevel level;
}

// ── View ──────────────────────────────────────────────────────────────────────
class const ToggleWrapTextIntent() extends Intent;

class const ToggleAutoScrollIntent() extends Intent;

class const IncreaseFontIntent() extends Intent;

class const DecreaseFontIntent() extends Intent;
