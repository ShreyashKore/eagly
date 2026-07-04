import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/eagly_info_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/features/home_screen/home_page.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService.init();
  await EaglyInfoService.init();
  await _configureDesktopWindow();
  await SentryFlutter.init((options) {
    options.dsn =
        'https://ae4a6b39a9a2ca819748de8112255cb6@o4511675750416384.ingest.us.sentry.io/4511675759984640';
    // Adds request headers and IP for users, for more info visit:
    // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
    options.sendDefaultPii = true;
    options.enableLogs = true;
    // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
    // We recommend adjusting this value in production.
    options.tracesSampleRate = 1.0;
    // The sampling rate for profiling is relative to tracesSampleRate
    // Setting to 1.0 will profile 100% of sampled transactions:
    options.profilesSampleRate = 1.0;
    // Configure Session Replay
    options.replay.sessionSampleRate = 0.1;
    options.replay.onErrorSampleRate = 1.0;
  }, appRunner: () => runApp(SentryWidget(child: const MyApp())));
}

/// Removes the native title bar on desktop so the in-app [AppHeader] can act as
/// the window header. macOS keeps its traffic-light controls; Windows/Linux get
/// custom caption buttons in the header. Dragging is handled by a drag region
/// in the header.
Future<void> _configureDesktopWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    minimumSize: Size(760, 520),
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: PreferencesService.themeModeListenable,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: AppConstants.appName,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
