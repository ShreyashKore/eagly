import 'dart:io';

import 'package:eagly/data/app_install_conflict.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/presentation/components/install_conflict_dialog.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  late FakeSessionService service;
  late DeviceSessionController session;
  late List<String> messages;

  /// Completes once the dialog, and any retry, are done.
  late Future<void> presented;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    final device = Device.android('SERIAL', 'device', model: 'Pixel 8');
    service = FakeSessionService(device)
      ..installResult = const DeviceCommandResult(
        error:
            'The installed copy of com.example.app is signed with a '
            'different key.',
        installConflict: AppInstallConflict(
          kind: AppInstallConflictKind.signature,
          packageName: 'com.example.app',
        ),
      );
    session = DeviceSessionController(device: device, service: service);
    messages = [];
  });

  tearDown(() => session.dispose());

  /// Installs a fresh APK and starts presenting the result as [presented].
  Future<void> install(WidgetTester tester) async {
    final apk = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('eagly_conflict');
      addTearDown(() => dir.delete(recursive: true));
      return File('${dir.path}/demo.apk')..writeAsStringSync('apk');
    }))!;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = (await tester.runAsync(
      () => session.installAppFromPath(apk.path),
    ))!;
    presented = presentAppInstallResult(
      context,
      session: session,
      result: result,
      showMessage: messages.add,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a signature conflict asks instead of only reporting it', (
    tester,
  ) async {
    await install(tester);

    expect(find.text('Replace com.example.app?'), findsOneWidget);
    expect(find.textContaining('signed with a different key'), findsOneWidget);
    expect(find.textContaining('permanently deletes its data'), findsOneWidget);
    expect(messages, isEmpty);

    await tester.tap(find.text('Keep installed app'));
    await tester.pumpAndSettle();
    await presented;

    expect(service.uninstallRequests, isEmpty);
    expect(service.installRequests, hasLength(1));
    expect(messages, isEmpty);
  });

  testWidgets('confirming uninstalls the installed copy and installs again', (
    tester,
  ) async {
    await install(tester);
    service.installResult = DeviceCommandResult.success(message: 'Success');

    await tester.tap(find.text('Uninstall and install'));
    await tester.runAsync(() => presented);
    await tester.pumpAndSettle();

    expect(service.uninstallRequests, ['com.example.app']);
    expect(service.installRequests, hasLength(2));
    expect(messages, ['Installed demo.apk on ${session.device.displayName}.']);
  });
}
