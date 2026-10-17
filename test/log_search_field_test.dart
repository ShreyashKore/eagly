import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/log_controller.dart';
import 'package:eagly/features/logs/presentation/components/log_search_field.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<LogController> pumpSearchField(WidgetTester tester) async {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    addTearDown(session.dispose);
    final log = session.logSessionManager.selectedTab!;
    log.logs = [
      LogEntry(
        timestamp: '2026-04-26 10:00:00.000',
        pid: '1',
        tid: '1',
        level: 'E',
        tag: 'Net',
        message: 'socket timeout',
      ),
      LogEntry(
        timestamp: '2026-04-26 10:00:01.000',
        pid: '1',
        tid: '1',
        level: 'I',
        tag: 'Net',
        message: 'connected',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              child: ListenableBuilder(
                listenable: log,
                builder: (context, _) => LogSearchField(controller: log),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  // The control draws the border; the field inside must not add the theme's
  // enabled / focused border or fill as a second box.
  void expectBareDecoration(WidgetTester tester, Finder field) {
    final decoration = tester
        .widget<InputDecorator>(
          find.descendant(of: field, matching: find.byType(InputDecorator)),
        )
        .decoration;
    expect(decoration.filled, isFalse);
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
  }

  testWidgets('the focused search field draws no inner border', (
    WidgetTester tester,
  ) async {
    final log = await pumpSearchField(tester);
    log.searchFocusNode.requestFocus();
    await tester.pumpAndSettle();

    expectBareDecoration(tester, find.byType(TextField));
  });

  testWidgets('typing searches, shows the count, and Escape clears it', (
    WidgetTester tester,
  ) async {
    final log = await pumpSearchField(tester);

    expect(find.text('Search logs'), findsOneWidget);
    expect(log.searchBarVisible, isFalse);

    await tester.enterText(find.byType(TextField), 'timeout');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(log.searchBarVisible, isTrue);
    expect(log.appliedInlineSearch.query, 'timeout');
    expect(find.text('1/1'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(log.searchBarVisible, isFalse);
    expect(log.inlineSearch.query, isEmpty);
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('⌘F on a selection fills and focuses the field', (
    WidgetTester tester,
  ) async {
    final log = await pumpSearchField(tester);

    log.setSelectedSearchText('connected');
    log.activateSearchFromSelection();
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'connected');
    expect(log.searchFocusNode.hasFocus, isTrue);
    expect(find.text('1/1'), findsOneWidget);
  });
}
