import 'package:eagly/data/device.dart';
import 'package:eagly/features/layout_inspector/components/layout_screen_canvas.dart';
import 'package:eagly/features/layout_inspector/layout_inspector_controller.dart';
import 'package:eagly/features/layout_inspector/layout_inspector_feature_view.dart';
import 'package:eagly/features/layout_inspector/services/inspector_helper.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/layout_inspector_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  DeviceSessionController sessionFor(DevicePlatform platform) {
    final device = Device(
      platform == DevicePlatform.android ? 'emulator-5554' : '00008140-0001',
      'device',
      platform: platform,
      model: 'Phone',
    );
    final service = FakeSessionService(device)
      ..startHelper = () => InspectorHelper.attach(
        FakeHelperProcess(
          respond: (method, _) =>
              method == 'snapshot' ? helperSnapshotResult() : null,
        ),
      );
    return DeviceSessionController(device: device, service: service);
  }

  Future<void> pumpView(
    WidgetTester tester,
    LayoutInspectorController controller,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: LayoutInspectorFeatureView(
            controller: controller,
            onClose: () {},
          ),
        ),
      ),
    );
  }

  /// Opens the pane on a session and captures, outside the fake clock: the
  /// helper is spoken to over streams.
  Future<LayoutInspectorController> captured(
    WidgetTester tester,
    DeviceSessionController session,
  ) async {
    final controller = session.layoutInspectorController;
    await tester.runAsync(() async {
      session.workspaceLayout.show(WorkspacePane.layoutInspector);
      await controller.capture();
    });
    return controller;
  }

  testWidgets('shows the tree, and a clicked row\'s details', (tester) async {
    final session = sessionFor(DevicePlatform.android);
    final controller = await captured(tester, session);
    await pumpView(tester, controller);

    expect(find.text('4 nodes'), findsOneWidget);
    expect(find.text('Example (application)'), findsOneWidget);
    expect(
      find.text('Click the screen or a row to inspect a node.'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('#sign_in'));
    await tester.pump();
    expect(controller.selected?.key, '1.1');
    expect(find.text('com.example.app:id/sign_in'), findsOneWidget);
    expect(find.text('Copy as'), findsOneWidget);

    await tester.runAsync(() async => session.dispose());
  });

  testWidgets('a click on the screenshot selects the node under it', (
    tester,
  ) async {
    final session = sessionFor(DevicePlatform.android);
    final controller = await captured(tester, session);
    await pumpView(tester, controller);

    final screen = tester.getRect(
      find.descendant(
        of: find.byType(LayoutScreenCanvas),
        matching: find.byType(AspectRatio),
      ),
    );
    // The button spans y 2100–2244 of 2400.
    await tester.tapAt(
      screen.topLeft + Offset(screen.width * 0.5, screen.height * 0.905),
    );
    await tester.pump();
    expect(controller.selected?.text, 'Sign in');

    await tester.runAsync(() async => session.dispose());
  });

  testWidgets('an iPhone is told the pane is Android only', (tester) async {
    final session = sessionFor(DevicePlatform.ios);
    expect(session.canInspectLayout, isFalse);
    expect(session.supportsPane(WorkspacePane.layoutInspector), isFalse);
    await pumpView(tester, session.layoutInspectorController);
    expect(find.text('Android only, for now'), findsOneWidget);
    session.dispose();
  });
}
