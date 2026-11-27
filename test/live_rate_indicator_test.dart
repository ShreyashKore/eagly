import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/presentation/components/live_rate_indicator.dart';
import 'package:eagly/features/logs/presentation/components/log_status_bar.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  var count = 0;

  Future<void> pumpIndicator(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    count = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: LiveRateIndicator(
                readCount: () => count,
                color: Colors.green,
              ),
            ),
          ),
        ),
      ),
    );
  }

  LiveRateSparklinePainter sparkline(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('live-rate-sparkline')),
              )
              .painter!
          as LiveRateSparklinePainter;

  testWidgets('samples the counter once a second', (tester) async {
    await pumpIndicator(tester);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('0 lines/s'), findsOneWidget);

    for (final lines in [40, 60, 50]) {
      count += lines;
      await tester.pump(const Duration(seconds: 1));
    }
    expect(sparkline(tester).rates, [40, 60, 50]);
    // The readout averages the last three seconds.
    expect(find.text('50 lines/s'), findsOneWidget);

    count += 2400;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('837 lines/s'), findsOneWidget); // (60+50+2400)/3
  });

  testWidgets('keeps only the last 30 seconds', (tester) async {
    await pumpIndicator(tester);
    for (var i = 0; i < 40; i++) {
      count += i;
      await tester.pump(const Duration(seconds: 1));
    }
    final rates = sparkline(tester).rates;
    expect(rates, hasLength(LiveRateIndicator.historyLength));
    expect(rates.first, 10);
    expect(rates.last, 39);
  });

  testWidgets('the pulse is one beat per sample, so tests still settle', (
    tester,
  ) async {
    await pumpIndicator(tester);
    count += 5;
    await tester.pump(const Duration(seconds: 1));
    // The beat is running...
    expect(tester.binding.hasScheduledFrame, isTrue);
    // ...and ends well before the next sample: pumpAndSettle returns.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('with animations off the dot stays still', (tester) async {
    await pumpIndicator(tester, disableAnimations: true);
    count += 5;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5 lines/s'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the status bar shows it only while lines are streaming', (
    tester,
  ) async {
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
    );
    final service = FakeSessionService(device);
    final session = DeviceSessionController(device: device, service: service);
    final controller = session.logSessionManager.selectedTab!;

    Future<void> pumpBar() => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => LogStatusBar(
              controller: controller,
              appMemoryBytes: 0,
              deviceDisplayName: 'Pixel',
            ),
          ),
        ),
      ),
    );

    await pumpBar();
    expect(find.byType(LiveRateIndicator), findsNothing);
    expect(find.text('Stopped'), findsOneWidget);

    await controller.startLogcat();
    await tester.pump();
    expect(find.byType(LiveRateIndicator), findsOneWidget);

    service.emit(testLogEntry(message: 'one'));
    service.emit(testLogEntry(message: 'two'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 lines/s'), findsOneWidget);

    controller.togglePauseResume();
    await tester.pump();
    expect(find.byType(LiveRateIndicator), findsNothing);
    expect(find.text('Paused'), findsOneWidget);

    // Timers are checked when the body ends, before tearDown.
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
