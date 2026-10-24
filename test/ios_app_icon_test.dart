import 'dart:typed_data';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:eagly/features/wireless_connection/data/wireless_debug_models.dart';
import 'package:eagly/services/device_session_repository.dart';
import 'package:eagly/services/ios/ios_app_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone whose SpringBoard answers every icon request with [icon], or fails
/// when [fails] is set, recording each request.
class _FakeIosAppService implements IosAppService {
  Uint8List? icon;
  bool fails = false;
  final List<({String deviceId, String bundleId})> iconRequests = [];

  @override
  Future<Uint8List?> fetchAppIcon({
    required String deviceId,
    required String bundleId,
  }) async {
    iconRequests.add((deviceId: deviceId, bundleId: bundleId));
    if (fails) throw StateError('SpringBoard went away');
    return icon;
  }

  @override
  Future<List<AppInfo>> listApps(String deviceId) async => const [];

  @override
  Future<DeviceCommandResult> installApp({
    required String deviceId,
    required String appPath,
  }) => throw UnimplementedError();

  @override
  Future<DeviceCommandResult> uninstallApp({
    required String deviceId,
    required String bundleId,
  }) => throw UnimplementedError();
}

void main() {
  late _FakeIosAppService apps;
  late DeviceSessionRepository repository;

  setUp(() {
    apps = _FakeIosAppService();
    repository = DeviceSessionRepository(
      device: const IosDevice('00008140-0001', 'device'),
      iosAppService: apps,
    );
  });

  test('an iOS app icon comes from SpringBoard, with no label', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    apps.icon = png;

    final details = await repository.fetchAppDetails('com.example.notes');

    expect(details, isNotNull);
    expect(details!.icon, png);
    expect(details.label, isNull);
    expect(apps.iconRequests, [
      (deviceId: '00008140-0001', bundleId: 'com.example.notes'),
    ]);
  });

  test('a backend that cannot read icons settles on no icon', () async {
    apps.icon = null;

    final details = await repository.fetchAppDetails('com.example.notes');

    // Not null: null would have the Apps pane retry an icon that never comes.
    expect(details, isNotNull);
    expect(details!.icon, isNull);
    expect(details.label, isNull);
  });

  test('a failed icon read is null, so the Apps pane retries it', () async {
    apps.fails = true;

    expect(await repository.fetchAppDetails('com.example.notes'), isNull);
  });
}
