import 'dart:io';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/crash_reports/components/body.dart';
import 'package:eagly/features/crash_reports/crash_report_controller.dart';
import 'package:eagly/features/crash_reports/data/crash_report.dart';
import 'package:eagly/services/ios/ios_crash_report_service.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  late Directory dir;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    dir = await Directory.systemTemp.createTemp('eagly_crash_search_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Writes each body to a report file named `<name>-2026-10-0N-100000.ips`
  /// and returns a controller that has pulled them.
  Future<CrashReportController> pulled(Map<String, String> bodies) async {
    final reports = <CrashReport>[];
    var day = 1;
    for (final MapEntry(key: name, value: body) in bodies.entries) {
      final fileName = '$name-2026-10-0${day++}-100000.ips';
      final file = File('${dir.path}/$fileName')..writeAsStringSync(body);
      reports.add(
        CrashReport(
          fileName: fileName,
          filePath: file.path,
          processName: name,
          timestamp: DateTime(2026, 10, day),
          sizeBytes: body.length,
        ),
      );
    }
    final device = Device.ios('UDID', 'iPhone');
    final service = FakeSessionService(device)
      ..crashReports = CrashReportPullResult(
        reports: reports,
        // The controller deletes this when it's done; the test's own
        // directory holds the files.
        outputDir: await Directory.systemTemp.createTemp('eagly_crash_out_'),
      );
    final session = DeviceSessionController(device: device, service: service);
    addTearDown(session.dispose);
    final controller = session.crashReportController;
    await controller.refresh();
    return controller;
  }

  Future<void> settled(CrashReportController controller) async {
    for (var i = 0; i < 100 && controller.isSearchingContent; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(controller.isSearchingContent, isFalse);
  }

  List<String> names(CrashReportController controller) => [
    for (final report in controller.filteredReports) report.processName,
  ];

  group('CrashReportController search', () {
    test('matches the process name at once, ignoring case', () async {
      final controller = await pulled({
        'Runner': '{"exception":"EXC_BAD_ACCESS"}',
        'Safari': '{"exception":"EXC_CRASH"}',
      });

      controller.setSearchText('  rUnNeR ');

      expect(names(controller), ['Runner']);
    });

    test('matches the file name', () async {
      final controller = await pulled({'Runner': '{}', 'Safari': '{}'});

      controller.setSearchText('2026-10-02');

      expect(names(controller), ['Safari']);
    });

    test('matches report bodies once the content search lands', () async {
      final controller = await pulled({
        'Runner': '{"exception":"EXC_BAD_ACCESS"}',
        'Safari': '{"exception":"EXC_CRASH"}',
        'Mail': '{"exception":"exc_bad_access"}',
      });

      controller.setSearchText('EXC_BAD_ACCESS');
      expect(controller.isSearchingContent, isTrue);
      expect(names(controller), isEmpty);

      await settled(controller);
      expect(names(controller), unorderedEquals(['Runner', 'Mail']));
    });

    test('a newer query supersedes one still being searched', () async {
      final controller = await pulled({
        'Runner': 'needle-one',
        'Safari': 'needle-two',
      });

      controller.setSearchText('needle-one');
      controller.setSearchText('needle-two');
      await settled(controller);

      expect(names(controller), ['Safari']);
    });

    test('clearing the search shows every report again', () async {
      final controller = await pulled({'Runner': 'abc', 'Safari': 'xyz'});

      controller.setSearchText('abc');
      await settled(controller);
      expect(names(controller), ['Runner']);

      controller.setSearchText('');
      expect(controller.isSearchingContent, isFalse);
      expect(names(controller), ['Runner', 'Safari']);
    });
  });

  group('crash report list', () {
    Widget host(CrashReportController controller) => MaterialApp(
      // Not AppTheme: its Google Fonts fail to load inside runAsync, which
      // the content search's isolate needs.
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Body(controller: controller),
        ),
      ),
    );

    testWidgets('filters as you type and says when nothing matches', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () => pulled({'Runner': 'abc', 'Safari': 'xyz'}),
      ))!;
      await tester.pumpWidget(host(controller));
      expect(find.text('Runner'), findsOneWidget);
      expect(find.text('Safari'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'saf');
      await tester.pump();
      expect(find.text('Runner'), findsNothing);
      expect(find.text('Safari'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nothing-here');
      // The debounce runs on the test's clock, the isolate on the real one.
      await tester.pump(CrashReportController.contentSearchDelay);
      for (var i = 0; i < 100 && controller.isSearchingContent; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('No matching crash reports'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Runner'), findsOneWidget);
      expect(find.text('Safari'), findsOneWidget);
    });
  });
}
