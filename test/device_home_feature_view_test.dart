import 'package:eagly/data/device.dart';
import 'package:eagly/features/device_home/data/device_info.dart';
import 'package:eagly/features/device_home/data/device_performance_stats.dart';
import 'package:eagly/features/device_home/device_home_feature_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_test_support.dart';

class _StatsService extends FakeSessionService {
  _StatsService(super.device);

  @override
  Future<DevicePerformanceStats> fetchPerformanceStats() async {
    return const DevicePerformanceStats(
      cpu: CpuStats(
        coreCount: 8,
        loadAverage1m: 2.4,
        loadAverage5m: 1.9,
        loadAverage15m: 1.2,
      ),
      memory: MemoryStats(
        totalKb: 8 * 1024 * 1024,
        availableKb: 2 * 1024 * 1024,
        freeKb: 1024 * 1024,
      ),
    );
  }
}

void main() {
  late Device device;
  late _StatsService service;
  late DeviceSessionController session;

  setUp(() {
    device = Device(
      'RFCN20ABCDE',
      'device',
      platform: DevicePlatform.android,
      brand: 'Google',
      model: 'Pixel 8 Pro',
    );
    service = _StatsService(device);
    service.deviceInfoToReturn = const DeviceInfo(
      identity: DeviceIdentityInfo(osName: 'Android', osVersion: '14'),
      battery: DeviceBatteryInfo(
        percentage: 78,
        chargingState: BatteryChargingState.charging,
      ),
      storage: DeviceStorageInfo(
        totalBytes: 128 * 1024 * 1024 * 1024,
        usedBytes: 96 * 1024 * 1024 * 1024,
      ),
    );
    session = DeviceSessionController(device: device, service: service);
  });

  Future<void> pumpView(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: DeviceHomeFeatureView(
            session: session,
            homeController: session.homeController,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows identity, vitals and the feature launcher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpView(tester);

    expect(find.text('Android 14'), findsOneWidget);
    expect(find.text('Install App'), findsOneWidget);
    expect(find.text('BATTERY'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    session.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the last snapshot visible after a disconnect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpView(tester);
    expect(find.text('78%'), findsOneWidget);

    session.updateDevice(
      device.copyWith(connectionState: DeviceConnectionState.disconnected),
    );
    await tester.pump();

    expect(
      find.textContaining('disconnected', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Reload devices'), findsOneWidget);
    expect(find.text('Getting reconnected'.toUpperCase()), findsOneWidget);
    // The battery reading from before the drop is still on screen.
    expect(find.text('78%'), findsOneWidget);
    // …but nothing live can be triggered from it.
    final install = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Install App'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(install.onPressed, isNull);

    session.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
