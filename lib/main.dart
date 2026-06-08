import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/app_info_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/theme/app_theme.dart';
import 'package:eagly/ui/home_screen/home_page.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService.init();
  await AppInfoService.init();
  await _configureDesktopWindow();
  runApp(const MyApp());
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
