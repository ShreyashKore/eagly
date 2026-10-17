import 'package:eagly/data/device.dart';
import 'package:eagly/features/terminal/terminal_feature_view.dart';
import 'package:eagly/features/terminal/terminal_session_manager.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSessionService service;
  DeviceSessionController? session;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  TerminalSessionManager createManager({
    DeviceConnectionState connectionState = DeviceConnectionState.connected,
  }) {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
      brand: 'Google',
      model: 'Pixel 8',
      connectionState: connectionState,
    );
    service = FakeSessionService(device);
    session = DeviceSessionController(device: device, service: service);
    return session!.terminalSessionManager;
  }

  tearDown(() {
    session?.dispose();
    session = null;
  });

  Widget host(TerminalSessionManager manager) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: TerminalFeatureView(manager: manager, onClose: () {}),
      ),
    );
  }

  testWidgets('shows the target device in the prompt', (tester) async {
    final manager = createManager();
    await tester.pumpWidget(host(manager));

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Google Pixel 8'), findsOneWidget);
    expect(find.text(r'$'), findsOneWidget);
  });

  testWidgets('submitting a line runs it on the bound device', (tester) async {
    final manager = createManager();
    await tester.pumpWidget(host(manager));

    await tester.enterText(find.byType(TextField), 'adb shell getprop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(service.terminalRequests.single.arguments, [
      '-s',
      'emulator-5554',
      'shell',
      'getprop',
    ]);
    // The prompt echoes the typed line and the field is emptied for the next.
    expect(find.textContaining('adb shell getprop'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );

    await service.terminalProcesses.single.finish(0);
    await tester.pump();
  });

  testWidgets('the + button opens another tab with its own scrollback', (
    tester,
  ) async {
    final manager = createManager();
    await tester.pumpWidget(host(manager));

    await tester.enterText(find.byType(TextField), 'use auto');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('use auto'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(manager.tabs, hasLength(2));
    expect(manager.selectedIndex, 1);
    // The new tab has its own scrollback, so the first tab's echo is gone.
    expect(find.textContaining('use auto'), findsNothing);
  });

  testWidgets('Enter runs the line, Shift+Enter keeps editing', (tester) async {
    final manager = createManager();
    await tester.pumpWidget(host(manager));

    await tester.enterText(find.byType(TextField), 'adb shell ls');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(service.terminalRequests, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(service.terminalRequests, hasLength(1));

    await service.terminalProcesses.single.finish(0);
    await tester.pump();
  });

  testWidgets('the editor is multi-line and monospaced', (tester) async {
    final manager = createManager();
    await tester.pumpWidget(host(manager));

    final mono = AppTheme.darkTheme.extension<EaglyTheme>()!.monoStyle;
    expect(mono.fontFamily, isNotNull);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, greaterThan(1));
    expect(field.style?.fontFamily, mono.fontFamily);

    // The scrollback shares the same face, so output lines stay in columns.
    final notice = tester.widget<Text>(find.textContaining('Commands run on'));
    expect(notice.style?.fontFamily, mono.fontFamily);
  });

  testWidgets('a disconnected device is called out in the prompt hint', (
    tester,
  ) async {
    final manager = createManager(
      connectionState: DeviceConnectionState.disconnected,
    );
    await tester.pumpWidget(host(manager));

    expect(find.text('Google Pixel 8 is disconnected'), findsOneWidget);
  });
}
