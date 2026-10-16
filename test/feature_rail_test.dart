import 'package:eagly/data/device.dart';
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
}
