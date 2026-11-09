import 'package:eagly/data/device.dart';
import 'package:eagly/features/home_screen/components/rail_button.dart';
import 'package:eagly/features/home_screen/feature_rail.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/presentation/theme/app_zoom.dart';
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

  /// Pumps the rail at [zoomLevel] and returns how far each label's
  /// `FittedBox` had to shrink it — 1.0 is drawn at full size.
  Future<Map<String, double>> labelScales(
    WidgetTester tester,
    DeviceSessionController session,
    double zoomLevel,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) =>
            AppZoom(zoomLevel: zoomLevel, child: child!),
        home: Scaffold(
          body: Row(
            children: [
              FeatureRail(
                session: session,
                onInstall: () {},
                onOpenSettings: () {},
              ),
            ],
          ),
        ),
      ),
    );
    return {
      for (final label in ['Home', 'Logs', 'Install', 'Settings'])
        label:
            tester
                .getSize(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(FittedBox),
                  ),
                )
                .width /
            tester.getSize(find.text(label)).width,
    };
  }

  testWidgets('the rail widens with the zoom instead of squeezing labels', (
    tester,
  ) async {
    final device = Device.android('SERIAL', 'device', model: 'Pixel 8');
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    addTearDown(session.dispose);

    final unzoomed = await labelScales(tester, session, 1.0);
    expect(tester.getSize(find.byType(FeatureRail)).width, 72);

    final zoomed = await labelScales(tester, session, 1.8);
    expect(
      tester.getSize(find.byType(FeatureRail)).width,
      moreOrLessEquals(72 * 1.8),
    );
    for (final label in unzoomed.keys) {
      expect(
        zoomed[label],
        greaterThanOrEqualTo(unzoomed[label]!),
        reason: '"$label" is squeezed harder when zoomed in',
      );
    }
  });

  group('focus tray', () {
    late DeviceSessionController session;

    setUp(() {
      final device = Device.android('SERIAL', 'device', model: 'Pixel 8');
      session = DeviceSessionController(
        device: device,
        service: FakeSessionService(device),
      );
    });
    tearDown(() => session.dispose());

    Future<void> pumpRail(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Row(
            children: [
              FeatureRail(
                session: session,
                onInstall: () {},
                onOpenSettings: () {},
              ),
            ],
          ),
        ),
      ),
    );

    Rect trayRect(WidgetTester tester) => tester.getRect(
      find.byElementPredicate(
        (element) => element.widget.runtimeType.toString() == '_FocusTray',
      ),
    );

    Rect buttonRect(WidgetTester tester, String label) => tester.getRect(
      find.ancestor(of: find.text(label), matching: find.byType(RailButton)),
    );

    RailButton button(WidgetTester tester, String label) => tester.widget(
      find.ancestor(of: find.text(label), matching: find.byType(RailButton)),
    );

    testWidgets(
      'slides from Home to the panes and back, stretching on the way',
      (tester) async {
        await pumpRail(tester);
        final home = buttonRect(tester, 'Home');
        final logs = buttonRect(tester, 'Logs');
        expect(trayRect(tester).contains(home.center), isTrue);
        expect(trayRect(tester).contains(logs.center), isFalse);

        session.openLogs();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        // Midway the leading (bottom) edge is already past Logs while the top
        // still reaches Home: the tray stretches across both.
        final midway = trayRect(tester);
        expect(midway.contains(logs.center), isTrue);
        expect(midway.top, lessThan(logs.top));

        await tester.pumpAndSettle();
        final settled = trayRect(tester);
        expect(settled.contains(logs.center), isTrue);
        expect(settled.contains(home.center), isFalse);

        session.openHome();
        await tester.pumpAndSettle();
        expect(trayRect(tester).contains(home.center), isTrue);
        expect(trayRect(tester).contains(logs.center), isFalse);
      },
    );

    testWidgets('panes open under Home are parked, not active', (tester) async {
      await pumpRail(tester);
      session.openLogs();
      await tester.pumpAndSettle();
      expect(button(tester, 'Logs').isActive, isTrue);
      expect(button(tester, 'Logs').parked, isFalse);
      expect(button(tester, 'Home').isActive, isFalse);

      session.openHome();
      await tester.pumpAndSettle();
      expect(button(tester, 'Home').isActive, isTrue);
      expect(button(tester, 'Logs').isActive, isFalse);
      expect(button(tester, 'Logs').parked, isTrue);
      expect(button(tester, 'Logs').tooltip, 'Back to logs');
      expect(button(tester, 'Files').parked, isFalse);

      // The caption leads back to the parked panes.
      await tester.tap(find.text('PANES'));
      await tester.pumpAndSettle();
      expect(session.isHomeOpen, isFalse);
      expect(button(tester, 'Logs').isActive, isTrue);
    });
  });
}
