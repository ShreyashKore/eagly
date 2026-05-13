// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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
    ScrollController? scrollController,
    Map<String, double> columnWidths = const <String, double>{},
    String searchQuery = '',
    bool caseSensitive = false,
    bool wholeWord = false,
    bool regexSearch = false,
    int? currentMatchLogIndex,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        darkTheme: AppTheme.darkTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
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
              scrollController: scrollController ?? ScrollController(),
              wrapText: wrapText,
              columnWidths: columnWidths,
              searchQuery: searchQuery,
              caseSensitive: caseSensitive,
              wholeWord: wholeWord,
              regexSearch: regexSearch,
              currentMatchLogIndex: currentMatchLogIndex,
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
        theme: AppTheme.lightTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        darkTheme: AppTheme.darkTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
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

  Future<void> pumpToggleableLogViewer(
    WidgetTester tester, {
    List<LogEntry>? logs,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        darkTheme: AppTheme.darkTheme.copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: _ToggleableLogViewerHarness(
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

  List<Offset> selectionDetectorCenters(
    WidgetTester tester,
    Iterable<int> rowIndices, {
    int detectorIndex = 0,
  }) {
    return [
      for (final rowIndex in rowIndices)
        tester.getCenter(
          find.byKey(ValueKey('row-selection-detector-$rowIndex-$detectorIndex')),
        ),
    ];
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

  testWidgets('focused search match scrolls horizontally to reveal the term', (
    WidgetTester tester,
  ) async {
    final scrollController = ScrollController();
    final message = '${List.filled(220, 'prefix').join(' ')} needle tail';
    final logs = [
      LogEntry(
        timestamp: '04-20 10:00:00.000',
        pid: '123',
        tid: '456',
        level: 'I',
        tag: 'Tag',
        message: message,
      ),
    ];

    addTearDown(scrollController.dispose);

    await pumpLogViewer(
      tester,
      logs: logs,
      wrapText: false,
      scrollController: scrollController,
    );
    final initialDx = tester.getTopLeft(find.text('Message')).dx;

    await pumpLogViewer(
      tester,
      logs: logs,
      wrapText: false,
      scrollController: scrollController,
      searchQuery: 'needle',
      currentMatchLogIndex: 0,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    final revealedDx = tester.getTopLeft(find.text('Message')).dx;
    expect(revealedDx, lessThan(initialDx - 100));
  });

  testWidgets('special entries render as status tiles without selection cells', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(
      tester,
      logs: [
        LogEntry(
          timestamp: '04-20 10:00:00.000',
          pid: '101',
          tid: '201',
          level: 'I',
          tag: 'Tag',
          message: 'First message',
        ),
        LogEntry.loggingState(
          type: LogEntryType.paused,
          message: 'Paused live logging for emulator-5554.',
          processName: 'emulator-5554',
        ),
      ],
    );

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Paused live logging for emulator-5554.'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    expect(find.byKey(const ValueKey('row-selection-detector-0-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-selection-detector-1-0')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('special-log-row'))).height, lessThan(36));
  });

  testWidgets('special entries stay compact when wrapText is disabled', (
    WidgetTester tester,
  ) async {
    await pumpLogViewer(
      tester,
      wrapText: false,
      logs: [
        LogEntry.loggingState(
          type: LogEntryType.stopped,
          message:
              'Device disconnected; stopped capturing logs for Pixel 8 (emulator-5554) after a very long session message that should remain visually compact.',
          processName: 'Pixel 8 (emulator-5554)',
        ),
      ],
    );

    final specialRow = find.byKey(const ValueKey('special-log-row'));
    expect(specialRow, findsOneWidget);
    expect(tester.getSize(specialRow).width, lessThanOrEqualTo(720));
    expect(tester.getSize(specialRow).height, lessThan(36));
  });

  testWidgets(
    'moving the mouse without dragging does not change row selection',
    (WidgetTester tester) async {
      await pumpSelectableLogViewer(tester);
      final centers = selectionDetectorCenters(tester, [0, 1, 2]);

      await tester.tapAt(centers[0]);
      await tester.pumpAndSettle();
      expect(find.text('Selected rows: 0'), findsOneWidget);
      expect(find.text('Selection mode: on'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-selection-toolbar')), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);

      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: centers[1]);
      await tester.pump();
      await mouse.moveTo(centers[2]);
      await tester.pumpAndSettle();

      expect(find.text('Selected rows: 0'), findsOneWidget);
    },
  );

  testWidgets(
    'whole-row selection mode disables text selection and clear restores it',
    (WidgetTester tester) async {
      await pumpSelectableLogViewer(tester);
      final firstDetector = selectionDetectorCenters(tester, [0]).single;

      await tester.tapAt(firstDetector);
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byKey(const ValueKey('row-selection-toolbar')), findsOneWidget);
      expect(find.text('1 row selected'), findsOneWidget);

      await tester.tap(find.text('Second message'));
      await tester.pumpAndSettle();

      expect(find.text('Selected rows: 0,1'), findsOneWidget);
      expect(find.text('2 rows selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Selected rows: none'), findsOneWidget);
      expect(find.text('Selection mode: off'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-selection-toolbar')), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
    },
  );

  testWidgets('dragging across a special row only selects real log rows', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(
      tester,
      logs: [
        LogEntry(
          timestamp: '04-20 10:00:00.000',
          pid: '101',
          tid: '201',
          level: 'I',
          tag: 'Tag',
          message: 'First message',
        ),
        LogEntry.loggingState(
          type: LogEntryType.paused,
          message: 'Paused live logging for emulator-5554.',
          processName: 'emulator-5554',
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
    );
    final centers = selectionDetectorCenters(tester, [0, 2]);

    expect(centers, hasLength(2));

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: centers.first);
    await tester.pump();
    await mouse.down(centers.first);
    await tester.pump();
    await mouse.moveTo(centers.last);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('Selected rows: 0,2'), findsOneWidget);
  });

  testWidgets('dragging with the primary button selects each crossed row', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(tester);
    final centers = selectionDetectorCenters(tester, [0, 1, 2]);

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
    expect(find.text('Selected rows: 0,1,2'), findsOneWidget);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row-selection-rect')), findsNothing);
    expect(find.text('Selected rows: 0,1,2'), findsOneWidget);
  });

  testWidgets('shift-click selects the inclusive range from the anchor row', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(tester);
    final centers = selectionDetectorCenters(tester, [0, 1, 2]);

    await tester.tapAt(centers[0]);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(centers[2]);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(find.text('Selected rows: 0,1,2'), findsOneWidget);
  });

  testWidgets('secondary click still opens the copy menu after drag selection', (
    WidgetTester tester,
  ) async {
    await pumpSelectableLogViewer(tester);
    final centers = selectionDetectorCenters(tester, [0, 1, 2]);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: centers.first);
    await tester.pump();
    await mouse.down(centers.first);
    await tester.pump();
    await mouse.moveTo(centers.last);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('Selected rows: 0,1,2'), findsOneWidget);

    final secondaryMouse = await tester.startGesture(
      centers.last,
      kind: ui.PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await secondaryMouse.up();
    await tester.pumpAndSettle();

    expect(find.text('Copy message'), findsOneWidget);
    expect(find.text('Copy time + message'), findsOneWidget);
    expect(find.byKey(const ValueKey('row-selection-rect')), findsNothing);
  });

  testWidgets('turning row selection mode off keeps the selection area mounted', (
    WidgetTester tester,
  ) async {
    await pumpToggleableLogViewer(tester);

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('Selection mode: on'), findsOneWidget);

    final toggleButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('toggle-row-selection-mode')),
    );
    toggleButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      find.byKey(const ValueKey('log-viewer-selection-area')),
      findsOneWidget,
    );
    expect(find.text('Selection mode: off'), findsOneWidget);

    final selectionArea = find.byType(SelectionArea);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    final areaRect = tester.getRect(selectionArea);
    final start = areaRect.topLeft + const Offset(360, 48);
    final end = start + const Offset(140, 0);
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await tester.pump();
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row-selection-rect')), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
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
  bool _rowSelectionMode = false;

  String get _selectedRowsLabel =>
      _selected.isEmpty
      ? 'Selected rows: none'
      : 'Selected rows: ${(_selected.toList()..sort()).join(',')}';

  String get _selectionModeLabel =>
      'Selection mode: ${_rowSelectionMode ? 'on' : 'off'}';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool? _beginSelection(int index, {bool shiftPressed = false}) {
    if (shiftPressed) {
      setState(() {
        _rowSelectionMode = true;
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
      _rowSelectionMode = true;
      _anchorIndex = index;
      if (shouldSelect) {
        _selected.add(index);
      } else {
        _selected.remove(index);
        if (_selected.isEmpty) {
          _rowSelectionMode = false;
        }
      }
    });
    return shouldSelect;
  }

  void _setRowSelected(int index, bool selected) {
    setState(() {
      if (selected) {
        _rowSelectionMode = true;
        _selected.add(index);
      } else {
        _selected.remove(index);
        if (_selected.isEmpty) {
          _rowSelectionMode = false;
        }
      }
    });
  }

  void _setSelectedRows(Set<int> indices) {
    setState(() {
      _selected
        ..clear()
        ..addAll(indices);
      _rowSelectionMode = _selected.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _anchorIndex = null;
      _rowSelectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_selectedRowsLabel, key: const ValueKey('selected-rows-label')),
        Text(_selectionModeLabel, key: const ValueKey('selection-mode-label')),
        Expanded(
          child: SizedBox(
            width: 900,
            child: LogViewer(
              logs: widget.logs,
              scrollController: _scrollController,
              wrapText: true,
              rowSelectionMode: _rowSelectionMode,
              selectedRowIndices: _selected,
              onRowSelectionStart: _beginSelection,
              onSelectedRowsChanged: _setSelectedRows,
              onRowSelectionChanged: _setRowSelected,
              onClearRowSelection: _clearSelection,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleableLogViewerHarness extends StatefulWidget {
  const _ToggleableLogViewerHarness({required this.logs});

  final List<LogEntry> logs;

  @override
  State<_ToggleableLogViewerHarness> createState() =>
      _ToggleableLogViewerHarnessState();
}

class _ToggleableLogViewerHarnessState
    extends State<_ToggleableLogViewerHarness> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selected = <int>{};
  bool _rowSelectionMode = true;

  String get _selectionModeLabel =>
      'Selection mode: ${_rowSelectionMode ? 'on' : 'off'}';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool? _beginSelection(int index, {bool shiftPressed = false}) {
    final shouldSelect = !_selected.contains(index);
    setState(() {
      if (shouldSelect) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
    return shouldSelect;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_selectionModeLabel, key: const ValueKey('selection-mode-label')),
        TextButton(
          key: const ValueKey('toggle-row-selection-mode'),
          onPressed: () {
            setState(() {
              _rowSelectionMode = !_rowSelectionMode;
              if (!_rowSelectionMode) {
                _selected.clear();
              }
            });
          },
          child: const Text('Toggle row selection mode'),
        ),
        Expanded(
          child: SizedBox(
            width: 900,
            child: LogViewer(
              logs: widget.logs,
              scrollController: _scrollController,
              wrapText: true,
              rowSelectionMode: _rowSelectionMode,
              selectedRowIndices: _selected,
              onRowSelectionStart: _beginSelection,
              onSelectedRowsChanged: _setSelectedRows,
            ),
          ),
        ),
      ],
    );
  }
}


