import 'package:eagly/app_menu/app_menu_controller.dart';
import 'package:eagly/data/device.dart';
import 'package:eagly/features/home_screen/components/save_layout_button.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/devices_repository.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/device_session_manager.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';
import 'support/workspace_test_support.dart';

/// View → Save Layout: the open panes saved once, opened by every device
/// that opens afterwards, cut down to the panes it can host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  // Disconnected, so activating a session starts no capture.
  final android = Device(
    'emulator-5554',
    'offline',
    platform: DevicePlatform.android,
    model: 'Pixel 8',
  );
  final iphone = Device(
    '00008030-001',
    'offline',
    platform: DevicePlatform.ios,
    model: 'iPhone 15',
  );

  DeviceSessionController createSession(
    Device device,
    WorkspaceLayoutMemory memory,
  ) {
    final session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
      layoutMemory: memory,
    );
    addTearDown(session.dispose);
    return session;
  }

  /// Saves what an iPhone could have open: logs | crash reports, with the
  /// terminal along the bottom. Laid out directly, so no pane loads anything.
  void saveIphoneLayout(WorkspaceLayoutMemory memory) {
    final source = WorkspaceLayout(memory: memory)
      ..show(WorkspacePane.logs)
      ..show(WorkspacePane.crashReports)
      ..show(WorkspacePane.terminal);
    addTearDown(source.dispose);
    source.moveToEdge(WorkspacePane.terminal, DockSide.bottom);
    expect(describe(source.root), 'column(row(logs, crashReports), terminal)');
    memory.saved = source.root;
  }

  group('opening a device', () {
    test('without a saved layout, it opens on Home', () {
      final session = createSession(android, WorkspaceLayoutMemory())
        ..activate();

      expect(session.isHomeOpen, isTrue);
      expect(session.workspaceLayout.isEmpty, isTrue);
    });

    test('it opens the saved layout in the workspace', () {
      final memory = WorkspaceLayoutMemory();
      saveIphoneLayout(memory);

      final session = createSession(iphone, memory)..activate();

      expect(session.isHomeOpen, isFalse);
      expect(
        describe(session.workspaceLayout.root),
        'column(row(logs, crashReports), terminal)',
      );
    });

    test('panes the device cannot host are left out', () {
      final memory = WorkspaceLayoutMemory();
      saveIphoneLayout(memory);

      final session = createSession(android, memory)..activate();

      expect(session.supportsPane(WorkspacePane.crashReports), isFalse);
      expect(describe(session.workspaceLayout.root), 'column(logs, terminal)');
      expect(session.isCrashReportsOpen, isFalse);
    });

    test('a saved layout of only unsupported panes leaves Home showing', () {
      final memory = WorkspaceLayoutMemory();
      final source = WorkspaceLayout(memory: memory)
        ..show(WorkspacePane.crashReports);
      addTearDown(source.dispose);
      memory.saved = source.root;

      final session = createSession(android, memory)..activate();

      expect(session.isHomeOpen, isTrue);
      expect(session.workspaceLayout.isEmpty, isTrue);
    });

    test('a device already open keeps its panes', () {
      final memory = WorkspaceLayoutMemory();
      final session = createSession(android, memory)..activate();
      saveIphoneLayout(memory);

      session.activate(); // selecting its tab again

      expect(session.isHomeOpen, isTrue);
    });
  });

  group('matching the saved layout', () {
    test('nothing matches when no layout is saved', () {
      final session = createSession(android, WorkspaceLayoutMemory())
        ..openLogs();

      expect(session.matchesSavedLayout, isFalse);
    });

    test('a device opened with it matches, also once cut down', () {
      final memory = WorkspaceLayoutMemory();
      saveIphoneLayout(memory);

      expect(createSession(iphone, memory).matchesSavedLayout, isFalse);
      final iphoneSession = createSession(iphone, memory)..activate();
      final androidSession = createSession(android, memory)..activate();

      expect(iphoneSession.matchesSavedLayout, isTrue);
      // Without Crash Reports, as an Android device would open it.
      expect(androidSession.matchesSavedLayout, isTrue);
    });

    test('moving, resizing, opening or closing a pane stops matching', () {
      final memory = WorkspaceLayoutMemory();
      final session = createSession(android, memory)
        ..openLogs()
        ..openTerminal();
      memory.saved = session.workspaceLayout.root;
      expect(session.matchesSavedLayout, isTrue);

      final layout = session.workspaceLayout;
      // What a released divider drag leaves behind.
      layout.panels.setRoot(
        WorkspaceLayout.windowId,
        WorkspaceArrangement.withShare(
          layout.root!,
          WorkspacePane.terminal.id,
          0.25,
        ),
      );
      expect(session.matchesSavedLayout, isFalse, reason: 'resized');

      memory.saved = layout.root;
      layout.moveToEdge(WorkspacePane.terminal, DockSide.bottom);
      expect(session.matchesSavedLayout, isFalse, reason: 'moved');

      memory.saved = layout.root;
      session.openUtilities();
      expect(session.matchesSavedLayout, isFalse, reason: 'opened');

      memory.saved = layout.root;
      session.closeUtilities();
      expect(session.matchesSavedLayout, isFalse, reason: 'closed');
    });

    test('switching tabs still matches', () {
      final memory = WorkspaceLayoutMemory();
      final session = createSession(android, memory)
        ..openLogs()
        ..openTerminal();
      session.workspaceLayout.stackWith(
        WorkspacePane.terminal,
        WorkspacePane.logs,
      );
      memory.saved = session.workspaceLayout.root;

      session.workspaceLayout.panels.activate(WorkspacePane.logs.id);

      expect(describe(session.workspaceLayout.root), 'tabs(*logs, terminal)');
      expect(session.matchesSavedLayout, isTrue);
    });

    testWidgets('the header button hides while the layout is saved', (
      tester,
    ) async {
      final memory = WorkspaceLayoutMemory();
      final session = createSession(android, memory);
      Future<void> pumpButton() => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            // A fresh widget each time, as the header rebuilds on a save.
            body: SaveLayoutButton(session: session, onSave: () {}),
          ),
        ),
      );
      final button = find.text('Save layout');

      await pumpButton();
      expect(button, findsNothing, reason: 'no panes open');

      session.openLogs();
      await tester.pump();
      expect(button, findsOneWidget);

      memory.saved = session.workspaceLayout.root;
      await pumpButton();
      expect(button, findsNothing, reason: 'saved');

      session.openTerminal();
      await tester.pump();
      expect(button, findsOneWidget, reason: 'changed since');
    });
  });

  group('storage', () {
    test('the saved layout survives a restart', () {
      final memory = WorkspaceLayoutMemory.persisted();
      saveIphoneLayout(memory);
      expect(PreferencesService.savedWorkspaceLayout, isNotNull);

      final session = createSession(iphone, WorkspaceLayoutMemory.persisted())
        ..activate();

      expect(
        describe(session.workspaceLayout.root),
        'column(row(logs, crashReports), terminal)',
      );
    });

    test('it is kept apart from remembered placement', () {
      final memory = WorkspaceLayoutMemory.persisted();
      saveIphoneLayout(memory);
      final saved = PreferencesService.savedWorkspaceLayout;

      // Rearranging afterwards moves the remembered placement only.
      createSession(android, memory)
        ..openUtilities()
        ..openFiles();

      expect(PreferencesService.savedWorkspaceLayout, saved);
      expect(PreferencesService.workspaceLayout, isNot(saved));
    });

    test('an unreadable saved layout opens Home', () async {
      SharedPreferences.setMockInitialValues({
        'savedWorkspaceLayout': '{not json',
      });
      await PreferencesService.init();

      final session = createSession(android, WorkspaceLayoutMemory.persisted())
        ..activate();

      expect(session.isHomeOpen, isTrue);
    });
  });

  group('saving from the app', () {
    late FakeAdbTool adbTool;
    late DevicesRepository repository;
    late DeviceSessionManager manager;
    late AppMenuController menu;

    setUp(() async {
      adbTool = FakeAdbTool()
        ..androidDevices = [
          Device('emulator-5554', 'device', platform: DevicePlatform.android),
        ];
      repository = DevicesRepository.forTesting(
        adbTool: adbTool,
        iosDeviceService: FakeIosDeviceService(),
      );
      manager = DeviceSessionManager(
        repository: repository,
        serviceFactory: (device) => FakeSessionService(device),
      );
      menu = AppMenuController(manager);
      await repository.refreshDevices(force: true);
      await Future<void>.delayed(Duration.zero);
      addTearDown(() async {
        menu.dispose();
        manager.dispose();
        repository.dispose();
        await adbTool.disposeTool();
      });
    });

    test('Save Layout is offered once the device has panes open', () {
      final session = manager.selected!;
      expect(session.isHomeOpen, isTrue);
      expect(manager.canSaveLayout, isFalse);
      expect(menu.state.canSaveLayout, isFalse);

      session.openTerminal();

      expect(manager.canSaveLayout, isTrue);
      expect(menu.state.canSaveLayout, isTrue);
    });

    test('saving and clearing reach preferences and the menu', () {
      manager.selected!
        ..openLogs()
        ..openTerminal();
      expect(menu.state.hasSavedLayout, isFalse);

      menu.saveLayout();
      expect(manager.hasSavedLayout, isTrue);
      expect(menu.state.hasSavedLayout, isTrue);
      expect(
        describe(
          WorkspaceLayoutMemory.decode(PreferencesService.savedWorkspaceLayout),
        ),
        'row(logs, terminal)',
      );

      // Clear Saved Layout stays available from Home.
      manager.goHome();
      expect(menu.state.hasSavedLayout, isTrue);

      menu.clearSavedLayout();
      expect(manager.hasSavedLayout, isFalse);
      expect(menu.state.hasSavedLayout, isFalse);
      expect(PreferencesService.savedWorkspaceLayout, isNull);
    });
  });
}
