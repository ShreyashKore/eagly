import 'dart:io';

import 'package:eagly/app_menu/app_menu_controller.dart';
import 'package:eagly/command_palette/command_palette_items.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdbTool adbTool;
  late FakeIdeviceIdTool ideviceIdTool;
  late FakeIdeviceInfoTool ideviceInfoTool;
  late DevicesRepository repository;
  late Directory tempDir;
  DeviceSessionManager? manager;
  AppMenuController? menuController;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    adbTool = FakeAdbTool();
    ideviceIdTool = FakeIdeviceIdTool();
    ideviceInfoTool = FakeIdeviceInfoTool();
    repository = DevicesRepository.forTesting(
      adbTool: adbTool,
      ideviceIdTool: ideviceIdTool,
      ideviceInfoTool: ideviceInfoTool,
    );
    tempDir = Directory.systemTemp.createTempSync('command-palette-test');
  });

  tearDown(() async {
    menuController?.dispose();
    menuController = null;
    manager?.dispose();
    manager = null;
    repository.dispose();
    await adbTool.disposeTool();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    "includes the selected device's supported Utilities catalog commands",
    (tester) async {
      // Building the manager/repository involves real (non-fake-clock)
      // async work — run it outside testWidgets' fake-async zone so any
      // internal Future.delayed/Timer use actually resolves instead of
      // waiting forever for a pump that never advances a virtual clock.
      await tester.runAsync(() async {
        adbTool.androidDevices = [
          Device('emulator-5554', 'device', platform: DevicePlatform.android),
        ];
        manager = DeviceSessionManager(
          repository: repository,
          serviceFactory: (device) => FakeSessionService(device),
        );
        menuController = AppMenuController(manager!);

        await repository.refreshDevices(force: true);
        await Future<void>.delayed(Duration.zero);
      });

      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final items = buildCommandPaletteItems(
        context: context,
        manager: manager!,
        menuController: menuController!,
        onOpenSettings: () {},
        onShowAbout: () {},
        onQuit: () {},
        onInstallApp: () {},
        onExportLogs: () {},
        onShowWireless: () {},
        onImportLog: () {},
        onZoomIn: () {},
        onZoomOut: () {},
        onShowSnackBar: (_) {},
      );

      final utilityItems = items
          .where((item) => item.category == 'Utilities')
          .toList();

      expect(utilityItems, isNotEmpty);
      expect(utilityItems.map((item) => item.label), contains('Reboot device'));
      // Android-only commands built through adb carry the device command
      // line as their subtitle, matching the pane's own preview.
      final reboot = utilityItems.firstWhere(
        (item) => item.label == 'Reboot device',
      );
      expect(reboot.subtitle, contains('adb'));
    },
  );
}
