import 'dart:async';
import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/home_screen/components/install_progress_banner.dart';
import 'package:eagly/features/home_screen/components/rail_button.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  testWidgets('shows the app, device and elapsed time while installing', (
    tester,
  ) async {
    final device = Device.android('SERIAL', 'device', model: 'Pixel 8');
    final service = FakeSessionService(device)..installGate = Completer();
    final session = DeviceSessionController(device: device, service: service);
    addTearDown(session.dispose);

    final apk = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('eagly_install');
      addTearDown(() => dir.delete(recursive: true));
      return File('${dir.path}/demo.apk')..writeAsStringSync('apk');
    }))!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: InstallProgressBanner(session: session)),
      ),
    );
    expect(find.textContaining('Installing'), findsNothing);

    final install = session.installAppFromPath(apk.path);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Installing demo.apk'), findsOneWidget);
    expect(find.text('on ${device.displayName}'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Elapsed time reads the real clock, which widget tests don't fake.
    expect(find.text('0:00'), findsOneWidget);

    service.installGate!.complete();
    final result = await install;
    expect(result.isSuccess, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Installing'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a busy rail button spins without changing its height', (
    tester,
  ) async {
    Widget rail({required bool busy}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 64,
            child: RailButton(
              icon: Icons.system_update_outlined,
              label: 'Install',
              isActive: busy,
              busy: busy,
              tooltip: 'Install',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(rail(busy: false));
    final idle = tester.getSize(find.byType(RailButton));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(rail(busy: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(RailButton)), idle);
    await tester.pumpWidget(const SizedBox());
  });
}
