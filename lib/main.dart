import 'package:flutter/material.dart';
import 'package:logview/home_page.dart';
import 'package:logview/services/app_info_service.dart';
import 'package:logview/services/preferences_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService.init();
  await AppInfoService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB Logcat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        // Applies to Material buttons
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
