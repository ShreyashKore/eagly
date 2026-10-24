import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/features/mirror/services/ios_screen_capture.dart';
import 'package:eagly/services/eagly_info_service.dart';
import 'package:eagly/services/ios/ios_backend.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/app_zoom.dart';
import 'package:eagly/features/home_screen/home_page.dart';
import 'package:eagly/services/sentry_event_filter.dart';
import 'package:eagly/utils/record_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initIosBackend();
  // Captures a hot restart left running; a no-op on a fresh launch.
  unawaited(IosScreenCapture.stopAll());
  await PreferencesService.init();
  await EaglyInfoService.init();
  final recordMode = RecordMode.isRequested(args);
  if (recordMode) RecordMode.anonymizeDevices();
  await _configureDesktopWindow(recordMode: recordMode);
  // Only release builds report. Debug runs on developer machines filled the
  // dashboard with JIT hangs and debug-only assertions, and spent the quota.
  if (!kReleaseMode) {
    runApp(const MyApp());
    return;
  }
  await SentryFlutter.init((options) {
    options.dsn = 'https://ae4a6b39a9a2ca819748de8112255cb6@o4511675750416384.ingest.us.sentry.io/4511675759984640';
    // No IP addresses or request headers: stacks and breadcrumbs are enough to
    // debug, and users never agreed to send more. See
    // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
    options.sendDefaultPii = false;
    // Errors and app hangs only. Tracing, profiling, logs and session replay
    // each draw on a separate, capped quota.
    options.tracesSampleRate = 0;
    options.enableLogs = false;
    options.replay.sessionSampleRate = 0;
    options.replay.onErrorSampleRate = 0;
    // Filter non-critical or noisy Flutter errors (e.g. RenderFlex overflow)
    // to preserve Sentry dashboard hygiene and event quota.
    options.beforeSend = SentryEventFilter.beforeSend;
  }, appRunner: () => runApp(SentryWidget(child: const MyApp())));
}

/// Removes the native title bar on desktop so the in-app [AppHeader] can act as
/// the window header. macOS keeps its traffic-light controls; Windows/Linux get
/// custom caption buttons in the header. Dragging is handled by a drag region
/// in the header.
///
/// [recordMode] (`--record-mode`) locks the window to a fixed size for
/// product-video recording; see [RecordMode].
Future<void> _configureDesktopWindow({required bool recordMode}) async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    minimumSize: Size(560, 240),
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (recordMode) await RecordMode.applyWindowLayout();
    await windowManager.show();
    await windowManager.focus();
  });
}

class const MyApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: PreferencesService.themeModeListenable,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<double>(
          valueListenable: PreferencesService.zoomLevelListenable,
          builder: (context, zoomLevel, _) {
            return MaterialApp(
              title: AppConstants.appName,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              home: const HomeScreen(),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => AppZoom(
                zoomLevel: zoomLevel,
                child: SnackBarTheme(
                  data: Theme.of(context).snackBarTheme.copyWith(
                    width: _snackBarWidth(MediaQuery.sizeOf(context).width),
                  ),
                  child: child!,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Width for a floating snack bar inside a pane [availableWidth] logical
/// pixels wide: capped so it never spans a maximised desktop window, and
/// shrunk to leave a gutter on narrow ones. Snack bars that ask for their own
/// width (e.g. the zoom-level toast) still win over this default.
double _snackBarWidth(double availableWidth) {
  final withGutters = availableWidth - AppConstants.snackBarSideMargin * 2;
  return math.max(
    math.min(AppConstants.snackBarMinWidth, availableWidth),
    math.min(AppConstants.snackBarMaxWidth, withGutters),
  );
}
