import 'package:eagly/constants/app_constants.dart';
import 'package:eagly/services/app_info_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/theme/app_theme.dart';
import 'package:eagly/ui/home_screen/home_page.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService.init();
  await AppInfoService.init();
  // Register fvp (libmdk) as the desktop backend for the video_player plugin.
  // NOTE: do not pass the global 'lowLatency' option — it sets
  // avformat.fflags=+nobuffer, which drops the first keyframe and leaves the
  // scrcpy stream black until the next (sparse) keyframe. Low latency is instead
  // achieved per-player via setBufferRange() once the mirror is initialized
  // (see ScrcpyEmbeddedTool).
  fvp.registerWith();
  runApp(const MyApp());
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
