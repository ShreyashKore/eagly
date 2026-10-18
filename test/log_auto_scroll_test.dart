import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// Auto-scroll through bursts of logs. The list only estimates the height of
/// rows it hasn't laid out, so following the tail by animating to
/// `maxScrollExtent` aimed at a guess: on macOS's bouncing physics it ran
/// thousands of pixels past the real end — the blank pane behind the list —
/// and sprang back.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  testWidgets(
    'a burst of logs lands on the newest row without overshooting',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final device = Device(
        'emulator-5554',
        'device',
        platform: DevicePlatform.android,
      );
      final service = FakeSessionService(device);
      final session = DeviceSessionController(device: device, service: service);
      final log = session.logSessionManager.selectedTab!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: log,
              builder: (context, _) => LogViewer(
                logs: log.filteredLogs,
                scrollController: log.scrollController,
                listController: log.listController,
                wrapText: false,
              ),
            ),
          ),
        ),
      );
      await log.startLogcat();
      expect(log.autoScroll, isTrue);

      final position = log.scrollController.position;
      var worstOvershoot = 0.0;
      var line = 0;
      for (var burst = 0; burst < 6; burst++) {
        for (var i = 0; i < 600; i++) {
          service.emit(testLogEntry(message: 'Line ${line++}'));
        }
        // One flush interval, then a few frames for the scroll to settle.
        await tester.pump(const Duration(milliseconds: 300));
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final overshoot = position.pixels - position.maxScrollExtent;
          if (overshoot > worstOvershoot) worstOvershoot = overshoot;
        }

        final shown = log.filteredLogs.length;
        expect(
          log.listController.visibleRange?.$2,
          shown - 1,
          reason: 'burst $burst should end on the newest row',
        );
        expect(
          position.pixels,
          moreOrLessEquals(position.maxScrollExtent, epsilon: 0.5),
        );
      }
      expect(worstOvershoot, lessThan(1));

      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
