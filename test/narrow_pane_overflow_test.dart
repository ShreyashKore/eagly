import 'package:eagly/data/device.dart';
import 'package:eagly/features/file_manager/components/file_context_menu.dart';
import 'package:eagly/features/file_manager/components/file_list_view.dart';
import 'package:eagly/features/file_manager/data/device_file_entry.dart';
import 'package:eagly/features/file_manager/file_manager_controller.dart';
import 'package:eagly/features/file_manager/services/device_file_system.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_filter_area.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// A workspace pane can be dragged far narrower than its controls fit; these
/// panes must clip or drop columns rather than throw layout overflows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const widths = <double>[
    40,
    80,
    120,
    160,
    200,
    254,
    280,
    319,
    360,
    420,
    500,
    700,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  tearDown(() => FileManagerController.fileSystemFactory = null);

  DeviceSessionController session() {
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
    return session;
  }

  Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: 400, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('file list fits every pane width', (tester) async {
    FileManagerController.fileSystemFactory = (_) => _FakeFileSystem();
    final controller = session().fileManagerController;
    await controller.refresh();
    expect(controller.entries, isNotEmpty);
    final actions = FileManagerActions(
      onDownload: (_) {},
      onRename: (_) {},
      onDelete: (_) {},
      onUpload: () {},
      onNewFolder: () {},
    );

    for (final width in widths) {
      await pumpAt(
        tester,
        width,
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              FileListView(controller: controller, actions: actions),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }

    // Wide enough for every column; narrower panes drop Perms first.
    await pumpAt(
      tester,
      700,
      FileListView(controller: controller, actions: actions),
    );
    expect(find.text('Perms'), findsOneWidget);
    await pumpAt(
      tester,
      400,
      FileListView(controller: controller, actions: actions),
    );
    expect(find.text('Perms'), findsNothing);
    expect(find.text('Modified'), findsOneWidget);
    await pumpAt(
      tester,
      280,
      FileListView(controller: controller, actions: actions),
    );
    expect(find.text('Modified'), findsNothing);
    expect(find.text('Size'), findsOneWidget);
  });

  testWidgets('log filter row fits every pane width', (tester) async {
    final log = session().logSessionManager.selectedTab!;
    log.logs = [
      LogEntry(
        timestamp: '2026-10-16 10:00:00.000',
        pid: '1',
        tid: '1',
        level: 'E',
        tag: 'Net',
        message: 'socket timeout',
      ),
    ];
    log.filter.applyTyped('tag:Net -message:chatty ');
    // A query expands search to its widest: match options, count, arrows.
    await pumpAt(tester, 1100, LogFilterArea(controller: log));
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search logs',
      ),
      'timeout',
    );
    await tester.pumpAndSettle();
    expect(log.inlineSearch.query, 'timeout');

    for (final width in [...widths, 1100.0]) {
      await pumpAt(tester, width, LogFilterArea(controller: log));
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}

class _FakeFileSystem implements DeviceFileSystem {
  @override
  String get initialPath => '/sdcard';

  @override
  String get rootPath => '/';

  @override
  Future<List<DeviceFileEntry>> list(String path) async => [
    DeviceFileEntry(
      name: 'DCIM',
      path: '/sdcard/DCIM',
      type: DeviceFileType.directory,
      modified: DateTime(2026, 10, 16, 12),
      permissions: 'drwxrwx--x',
    ),
    DeviceFileEntry(
      name: 'a_rather_long_file_name_that_needs_an_ellipsis.mp4',
      path: '/sdcard/a_rather_long_file_name_that_needs_an_ellipsis.mp4',
      type: DeviceFileType.file,
      sizeBytes: 123456789,
      modified: DateTime(2026, 10, 16, 12),
      permissions: '-rw-rw----',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
