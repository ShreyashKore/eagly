// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logview/data/log_column.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/services/preferences_service.dart';
import 'package:logview/theme/app_theme.dart';
import 'package:logview/ui/log_viewer/log_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Future<void> pumpLogViewer(
    WidgetTester tester, {
    List<LogEntry>? logs,
    required bool wrapText,
    Map<String, double> columnWidths = const <String, double>{},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: LogViewer(
              logs:
                  logs ??
                  [
                    LogEntry(
                      timestamp: '04-20 10:00:00.000',
                      pid: '123',
                      tid: '456',
                      level: 'I',
                      tag: 'Tag',
                      message: 'short message',
                    ),
                  ],
              scrollController: ScrollController(),
              wrapText: wrapText,
              columnWidths: columnWidths,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSelectableLogViewer(
    WidgetTester tester, {
    List<LogEntry>? logs,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: _SelectableLogViewerHarness(
            logs:
                logs ??
                [
                  LogEntry(
                    timestamp: '04-20 10:00:00.000',
                    pid: '101',
                    tid: '201',
                    level: 'I',
                    tag: 'Tag',
                    message: 'First message',
                  ),
                  LogEntry(
                    timestamp: '04-20 10:00:01.000',
                    pid: '102',
                    tid: '202',
                    level: 'I',
                    tag: 'Tag',
                    message: 'Second message',
                  ),
                  LogEntry(
                    timestamp: '04-20 10:00:02.000',
                    pid: '103',
                    tid: '203',
                    level: 'I',
                    tag: 'Tag',
                    message: 'Third message',
                  ),
                ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<double?> messageColumnWidths(WidgetTester tester) {
    return tester
        .widgetList<SizedBox>(
          find.ancestor(
            of: find.text('Message'),
            matching: find.byType(SizedBox),
          ),
        )
        .map((box) => box.width);
  }

  List<Offset> selectionCellCenters(WidgetTester tester) {
    final finder = find.byIcon(Icons.check_box_outline_blank);
    return List<Offset>.generate(
      tester.widgetList<Icon>(finder).length,
      (index) => tester.getCenter(finder.at(index)),
    );
  }

  testWidgets('uses 4000px minimum width when wrapText is disabled', (
    WidgetTester tester,
  ) async {
    await pumpLogViewer(tester, wrapText: false);

    expect(
      messageColumnWidths(tester),
      contains(LogViewer.defaultUnwrappedMessageWidth),
    );
  });

  testWidgets('uses a manually expanded message width when it exceeds 4000', (
    WidgetTester tester,
  ) async {
    const largerWidth = 5321.5;

    await pumpLogViewer(
      tester,
      wrapText: false,
      columnWidths: {LogColumn.message.name: largerWidth},
    );

    expect(messageColumnWidths(tester), contains(largerWidth));
  });

  testWidgets('grows beyond 4000 based on a built long message', (
    WidgetTester tester,
  ) async {
    await pumpLogViewer(
      tester,
      wrapText: false,
      logs: [
        LogEntry(
          timestamp: '04-20 10:00:00.000',
          pid: '123',
          tid: '456',
          level: 'I',
          tag: 'Tag',
          message: List.filled(1000, 'W').join(),
        ),
      ],
    );

    expect(
      messageColumnWidths(tester).whereType<double>().any(
        (width) => width > LogViewer.defaultUnwrappedMessageWidth,
      ),
      isTrue,
    );
  });

  testWidgets(
    'moving the mouse without dragging does not change row selection',
    (WidgetTester tester) async {
      await pumpSelectableLogViewer(tester);
      final centers = selectionCellCenters(tester);

      await tester.tapAt(centers[0]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box), findsOneWidget);

      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: centers[1]);
      await tester.pump();
      await mouse.moveTo(centers[2]);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_box), findsOneWidget);
    },
  );

  testWidgets('dragging with the primary button selects each crossed row', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(tester);
    final centers = selectionCellCenters(tester);

    final first = centers[0];
    final third = centers[2];

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: first);
    await tester.pump();
    await mouse.down(first);
    await tester.pump();
    expect(find.byKey(const ValueKey('row-selection-rect')), findsOneWidget);
    await mouse.moveTo(third);
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsNWidgets(3));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row-selection-rect')), findsNothing);
    expect(find.byIcon(Icons.check_box), findsNWidgets(3));
  });

  testWidgets('shift-click selects the inclusive range from the anchor row', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(tester);
    final centers = selectionCellCenters(tester);

    await tester.tapAt(centers[0]);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(centers[2]);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(find.byIcon(Icons.check_box), findsNWidgets(3));
  });
}

class _SelectableLogViewerHarness extends StatefulWidget {
  const _SelectableLogViewerHarness({required this.logs});

  final List<LogEntry> logs;

  @override
  State<_SelectableLogViewerHarness> createState() =>
      _SelectableLogViewerHarnessState();
}

class _SelectableLogViewerHarnessState
    extends State<_SelectableLogViewerHarness> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selected = <int>{};
  int? _anchorIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool? _beginSelection(int index, {bool shiftPressed = false}) {
    if (shiftPressed) {
      setState(() {
        final anchor = _anchorIndex ?? index;
        _anchorIndex = anchor;
        final start = anchor < index ? anchor : index;
        final end = anchor > index ? anchor : index;
        for (var current = start; current <= end; current++) {
          _selected.add(current);
        }
      });
      return null;
    }

    final shouldSelect = !_selected.contains(index);
    setState(() {
      _anchorIndex = index;
      if (shouldSelect) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
    return shouldSelect;
  }

  void _setRowSelected(int index, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  void _setSelectedRows(Set<int> indices) {
    setState(() {
      _selected
        ..clear()
        ..addAll(indices);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 900,
      height: 400,
      child: LogViewer(
        logs: widget.logs,
        scrollController: _scrollController,
        wrapText: true,
        rowSelectionMode: true,
        selectedRowIndices: _selected,
        onRowSelectionStart: _beginSelection,
        onSelectedRowsChanged: _setSelectedRows,
        onRowSelectionChanged: _setRowSelected,
      ),
    );
  }
}
