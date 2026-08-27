import 'dart:math' as math;

import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/presentation/components/log_status_bar.dart';
import 'package:eagly/presentation/components/feature_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// Pane status bars must keep every readout: when the pane is too narrow they
/// scroll sideways instead of overflowing or truncating.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<void> pump(WidgetTester tester, double width, Widget bar) async {
    // The test font is much wider than the real one, so give the surface room.
    await tester.binding.setSurfaceSize(Size(math.max(width, 400), 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: bar),
          ),
        ),
      ),
    );
  }

  Widget statusBar(WidgetTester tester) {
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
    return LogStatusBar(
      controller: session.logSessionManager.selectedTab!,
      appMemoryBytes: 1234567,
      deviceDisplayName: 'Pixel',
    );
  }

  testWidgets('spreads across the full width when everything fits', (
    tester,
  ) async {
    await pump(tester, 1400, statusBar(tester));
    expect(tester.takeException(), isNull);

    final row = tester.getSize(find.byType(Row).first);
    expect(row.width, 1400 - 32); // full width minus the bar padding

    // The Spacer still pushes the trailing group to the right edge.
    expect(
      tester.getTopRight(find.text('Stopped')).dx,
      greaterThan(1000),
    );
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scrollable.controller?.position.maxScrollExtent ?? 0, 0);
  });

  testWidgets('scrolls instead of overflowing when the pane is narrow', (
    tester,
  ) async {
    await pump(tester, 300, statusBar(tester));
    expect(tester.takeException(), isNull);

    // Nothing is dropped: the row keeps its natural width and scrolls.
    expect(find.text('Logs: 0'), findsOne);
    expect(find.text('Stopped'), findsOne);
    expect(tester.getSize(find.byType(Row).first).width, greaterThan(300));

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    // Draggable with a mouse, not just a trackpad.
    await tester.drag(scrollable, const Offset(-120, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('an empty bar still fills the pane width', (tester) async {
    await pump(
      tester,
      200,
      const FeatureStatusBar(children: [Text('ok'), Spacer()]),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Row).first).width, 200 - 32);
  });
}
