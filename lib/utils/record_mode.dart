import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Developer-only launch mode for recording product videos: `--record-mode`
/// pins the window to a fixed, centred [windowSize] so every take is framed
/// identically.
///
/// Everything recording-specific lives here; removing the feature means
/// deleting this file and its two call sites in `main.dart`.
abstract final class RecordMode {
  /// Command-line flag that turns record mode on.
  static const flag = '--record-mode';

  /// Window size, in logical pixels, used while recording.
  static const windowSize = Size(1920, 1080);

  /// Whether [args] — the arguments the runner forwarded to `main` — ask for
  /// record mode.
  static bool isRequested(List<String> args) => args.contains(flag);

  /// Locks the window to [windowSize] and centres it. Call after
  /// `windowManager.ensureInitialized()` and before the window is shown.
  static Future<void> applyWindowLayout() async {
    await windowManager.setMinimumSize(windowSize);
    await windowManager.setMaximumSize(windowSize);
    await windowManager.setSize(windowSize);
    await windowManager.center();
  }
}
