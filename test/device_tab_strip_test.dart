import 'package:eagly/data/device.dart';
import 'package:eagly/features/home_screen/components/device_tab.dart';
import 'package:eagly/features/home_screen/components/device_tab_strip.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  DeviceSessionController tab(Device device) {
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    addTearDown(session.dispose);
    return session;
  }

  group('DeviceTabStrip.ambiguousLabels', () {
    // Only record mode's short names can collide.
    setUp(() => Device.shortNames = true);
    tearDown(() => Device.shortNames = false);

    test('different models need nothing more than their name', () {
      final tabs = [
        tab(Device.android('RZCW1186VXZ', 'device', brand: 'Samsung')),
        tab(Device.ios('00008140-001564CA3493801C', 'device', model: 'iPhone')),
      ];
      expect(DeviceTabStrip.ambiguousLabels(tabs), isEmpty);
    });

    test('two of one model are flagged so both add their serial', () {
      final tabs = [
        tab(Device.android('A1', 'device', brand: 'Google', model: 'Pixel 8')),
        tab(Device.android('B2', 'device', brand: 'Google', model: 'Pixel 8')),
        tab(Device.android('C3', 'device', brand: 'Google', model: 'Pixel 9')),
      ];
      expect(DeviceTabStrip.ambiguousLabels(tabs), {'Google Pixel 8'});
    });
  });

  testWidgets('the tab tooltip spells out the serial the tab cuts short', (
    tester,
  ) async {
    final session = tab(
      Device.android(
        'RZCW1186VXZ',
        'device',
        brand: 'Samsung',
        model: 'Galaxy S21',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: DeviceTab.minWidth,
              child: DeviceTab(
                session: session,
                selected: true,
                animateIn: false,
                onSelect: () {},
                onReload: null,
                onClose: null,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byTooltip('RZCW1186VXZ  ·  Samsung Galaxy S21'),
      findsOneWidget,
    );
  });

  group('DeviceTabStrip.fitTabWidths', () {
    const fit = DeviceTabStrip.fitTabWidths;

    test('tabs take only what they need when there is room', () {
      expect(fit([150, 300], 1000), [150, 300]);
      expect(fit([149.2], 1000), [150], reason: 'rounded up, never clipped');
    });

    test('a tab never grows past twice its old width', () {
      expect(fit([900], 2000), [DeviceTab.maxWidth]);
      expect(DeviceTab.maxWidth, 508);
    });

    test('when space runs out the widest tab gives way first', () {
      expect(fit([150, 500], 600), [150, 450]);
      expect(fit([100, 400, 500], 700), [100, 300, 300]);
    });

    test('shrinking stops at the minimum; past that the strip scrolls', () {
      expect(
        fit(List.filled(10, 300), 600),
        List.filled(10, DeviceTab.minWidth),
      );
      expect(fit([100, 600], 200), [
        100,
        DeviceTab.minWidth,
      ], reason: 'a tab already narrower than the minimum keeps its width');
    });
  });

  group('DeviceTabStrip layout', () {
    late FakeAdbTool adbTool;
    late DevicesRepository repository;
    DeviceSessionManager? manager;

    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.init();
    });

    setUp(() {
      adbTool = FakeAdbTool();
      repository = DevicesRepository.forTesting(
        adbTool: adbTool,
        iosDeviceService: FakeIosDeviceService(),
      );
    });

    tearDown(() async {
      manager?.dispose();
      manager = null;
      repository.dispose();
      await adbTool.disposeTool();
    });

    Future<List<double>> pumpStrip(WidgetTester tester, double width) async {
      await tester.runAsync(() async {
        adbTool.androidDevices = [
          Device.android('A1', 'device', brand: 'Google', model: 'Pixel 8'),
          Device.android(
            'B2',
            'device',
            brand: 'Samsung',
            model: 'Galaxy Z Fold6 Enterprise Edition',
          ),
        ];
        manager ??= DeviceSessionManager(
          repository: repository,
          serviceFactory: (device) => FakeSessionService(device),
        );
        await repository.refreshDevices(force: true);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 48,
                child: DeviceTabStrip(manager: manager!),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return [
        for (final element in find.byType(DeviceTab).evaluate())
          tester.getSize(find.byWidget(element.widget)).width,
      ];
    }

    testWidgets('a roomy strip leaves each tab at its own width', (
      tester,
    ) async {
      final widths = await pumpStrip(tester, 1400);

      expect(widths, hasLength(2));
      final [pixel, fold] = widths;
      expect(pixel, lessThan(fold), reason: 'a short name, a short tab');
      expect(pixel, lessThan(1400 / 2), reason: 'no padding to an even share');
      expect(fold, lessThanOrEqualTo(DeviceTab.maxWidth));
    });

    testWidgets('a tight strip shrinks the long tab and keeps the short one', (
      tester,
    ) async {
      final roomy = await pumpStrip(tester, 1400);
      // Room for the short tab's own width twice over, not for the long one.
      final tight = await pumpStrip(tester, roomy[0] * 2 + 60);

      expect(tight[0], roomy[0]);
      expect(tight[1], roomy[0] + 60, reason: 'the long tab takes the rest');
      expect(tight[1], lessThan(roomy[1]));
      expect(tight[1], greaterThanOrEqualTo(DeviceTab.minWidth));
    });
  });
}
