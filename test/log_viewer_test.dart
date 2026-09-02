import 'package:eagly/features/logs/data/models/log_column.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/utils/text_search_pattern.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  testWidgets(
    'unmounting mid-resize saves widths without rebuilding a locked tree',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final logs = List.generate(
        20,
        (index) => testLogEntry(message: 'Message $index'),
      );

      Map<String, double>? savedWidths;
      var showViewer = true;
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                if (!showViewer) return const SizedBox.shrink();
                return LogViewer(
                  logs: logs,
                  scrollController: scrollController,
                  wrapText: false,
                  rowSelectionMode: false,
                  selectedRowIndices: const {},
                  search: const TextSearchConfig(),
                  hiddenColumns: const {},
                  columnWidths: const {},
                  // The real controller notifies its listeners here, which
                  // rebuilds the pane — mimic that with a host setState.
                  onColumnWidthsChanged: (widths) {
                    savedWidths = widths;
                    setHostState(() {});
                  },
                  isIos: false,
                );
              },
            ),
          ),
        ),
      );

      final handle = find
          .byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.resizeColumn,
          )
          .first;
      await tester.drag(handle, const Offset(24, 0));
      await tester.pump();

      // Tear the viewer down before the 500 ms save debounce elapses: the
      // flush must not notify while the framework is unmounting the subtree.
      setHostState(() => showViewer = false);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The deferred flush still lands, so the resize is not lost.
      await tester.pump();
      expect(savedWidths, isNotNull);
      expect(savedWidths![LogColumn.values.first.name], isNotNull);
    },
  );

  testWidgets('unmounting with no pending resize does not save widths', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    var saveCount = 0;
    var showViewer = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              if (!showViewer) return const SizedBox.shrink();
              return LogViewer(
                logs: [testLogEntry(message: 'Message')],
                scrollController: scrollController,
                wrapText: false,
                rowSelectionMode: false,
                selectedRowIndices: const {},
                search: const TextSearchConfig(),
                hiddenColumns: const {},
                columnWidths: const {},
                onColumnWidthsChanged: (_) => saveCount++,
                isIos: false,
              );
            },
          ),
        ),
      ),
    );

    setHostState(() => showViewer = false);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(saveCount, 0);
  });
}
