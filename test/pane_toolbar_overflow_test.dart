import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/apps_feature_view.dart';
import 'package:eagly/features/file_manager/components/file_manager_toolbar.dart';
import 'package:eagly/presentation/components/overflow_toolbar.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// Feature panes stack side by side and are resizable, so every pane toolbar
/// has to survive a narrow pane: actions collapse into the overflow menu
/// instead of overflowing the row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  DeviceSessionController createSession() {
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
    return session;
  }

  Future<void> pump(WidgetTester tester, double width, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  group('file manager toolbar', () {
    Widget build(DeviceSessionController session) => FileManagerToolbar(
      controller: session.fileManagerController,
      onUpload: () {},
      onNewFolder: () {},
      onDownloadSelected: () {},
      onDeleteSelected: () {},
      onClose: () {},
    );

    testWidgets('shows every action when the pane is wide', (tester) async {
      await pump(tester, 700, build(createSession()));

      expect(find.byIcon(Icons.more_horiz).hitTestable(), findsNothing);
      expect(find.byIcon(Icons.upload_file_outlined).hitTestable(), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses actions when the pane is narrow', (tester) async {
      await pump(tester, 260, build(createSession()));
      expect(tester.takeException(), isNull);

      // Navigation and close never collapse.
      expect(find.byIcon(Icons.arrow_back).hitTestable(), findsOne);
      expect(find.byIcon(Icons.close).hitTestable(), findsOne);

      await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOne);
    });
  });

  group('apps toolbar', () {
    testWidgets('keeps the search field usable and collapses the toggle', (
      tester,
    ) async {
      final session = createSession();
      // Android sessions offer the system-apps toggle.
      await pump(
        tester,
        220,
        AppsFeatureView(controller: session.appsController, onClose: () {}),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final searchField = find.byType(TextField);
      expect(searchField, findsOne);
      expect(tester.getSize(searchField).width, greaterThanOrEqualTo(140));
      expect(find.byType(Switch).hitTestable(), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
      // Not pumpAndSettle: the apps list keeps a spinner running.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<ToolbarAction>),
          matching: find.text('System apps'),
        ),
        findsOne,
      );
    });
  });
}
