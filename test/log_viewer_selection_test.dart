import 'dart:math';

import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/presentation/components/log_viewer.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/utils/log_entry_utils.dart';
import 'package:eagly/utils/text_search_pattern.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';

/// Text selection over the live list. The list under the viewer's
/// `SelectionArea` streams, drops its head at the buffer cap, and is cleared
/// or swapped wholesale (a fresh capture, a filter), while a selection — or
/// the collapsed one a click leaves — points into its rows. Each of these used
/// to throw from Flutter's selection delegates (Sentry FLUTTER-B, -E, -4A,
/// -A3, -3T).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  List<LogEntry> makeLogs(int count, {String prefix = 'Message'}) =>
      List.generate(count, (i) => testLogEntry(message: '$prefix $i'));

  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  final desktop = TargetPlatformVariant(const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  group('after the selected rows scroll away', () {
    // The rows holding the selection are kept alive offscreen; the list has
    // to keep laying them out or the selection has no point for that edge.
    testWidgets('⇧↓ does not throw (FLUTTER-A3)', (tester) async {
      final host = await _Host.pump(tester, makeLogs(300));
      await _dragSelect(tester, 'Message 3', 'Message 6');
      host.scroll.jumpTo(3000);
      await tester.pump();

      await _withShift(tester, LogicalKeyboardKey.arrowDown);

      expect(tester.takeException(), isNull);
      await host.dispose(tester);
    }, variant: macOS);

    testWidgets('⌘A after a click does not throw (FLUTTER-4A)', (tester) async {
      final host = await _Host.pump(tester, makeLogs(300));
      await _click(tester, find.textContaining('Message 12').first);
      host.scroll.jumpTo(host.scroll.position.maxScrollExtent);
      await tester.pump();

      await _selectAll(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, contains('Message 299'));
      await host.dispose(tester);
    }, variant: macOS);

    testWidgets('rebuilding a kept-alive row does not throw (FLUTTER-B)', (
      tester,
    ) async {
      // Row 5 is the current search match, so it carries the viewer's
      // current-match key.
      final host = await _Host.pump(tester, makeLogs(300));
      host.update(
        search: const TextSearchConfig(query: 'Message'),
        currentMatch: 5,
      );
      await _pumpFrames(tester);
      await _click(tester, find.textContaining('Message 5').first);
      host.scroll.jumpTo(3000);
      await _pumpFrames(tester);

      // Stepping to a match near the viewport takes the key off row 5, which
      // rebuilds its text while the row is kept alive offscreen.
      host.update(currentMatch: 165);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      await host.dispose(tester);
    }, variant: macOS);
  });

  group('when the list changes under a selection', () {
    testWidgets('a fresh capture drops the selection', (tester) async {
      final host = await _Host.pump(tester, makeLogs(40));
      await _dragSelect(tester, 'Message 2', 'Message 9');
      expect(host.selectedText, contains('Message 5'));

      host.update(logs: const []);
      await _pumpFrames(tester);
      host.update(logs: makeLogs(5, prefix: 'Fresh'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, isNull);

      await _dragSelect(tester, 'Fresh 1', 'Fresh 3');
      expect(host.selectedText, contains('Fresh 2'));
      await host.dispose(tester);
    }, variant: desktop);

    testWidgets('a filter that hides the selected rows drops it', (
      tester,
    ) async {
      final host = await _Host.pump(tester, makeLogs(40));
      await _dragSelect(tester, 'Message 6', 'Message 12');

      host.update(logs: makeLogs(3, prefix: 'Filtered'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, isNull);
      await host.dispose(tester);
    }, variant: desktop);

    testWidgets('appending rows keeps the selection', (tester) async {
      final logs = makeLogs(20);
      final host = await _Host.pump(tester, logs);
      await _dragSelect(tester, 'Message 2', 'Message 4');
      final before = host.selectedText;
      expect(before, contains('Message 3'));

      logs.addAll(makeLogs(5, prefix: 'Later'));
      host.update();
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, before);
      await host.dispose(tester);
    }, variant: macOS);

    testWidgets('evicting rows far above the selection keeps it', (
      tester,
    ) async {
      final logs = makeLogs(300);
      final host = await _Host.pump(tester, logs);
      host.scroll.jumpTo(host.scroll.position.maxScrollExtent);
      await _pumpFrames(tester);
      await _dragSelect(tester, 'Message 280', 'Message 282');
      final before = host.selectedText;
      expect(before, contains('Message 281'));

      // The buffer cap drops its head, in place, as the controller does;
      // the selected rows only move up.
      logs.removeRange(0, 5);
      host.update();
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, before);
      expect(find.textContaining('Message 281'), findsOneWidget);
      await host.dispose(tester);
    }, variant: macOS);

    testWidgets('evicting a built row drops the selection', (tester) async {
      final logs = makeLogs(40);
      final host = await _Host.pump(tester, logs);
      await _dragSelect(tester, 'Message 30', 'Message 32');
      expect(host.selectedText, contains('Message 31'));

      // Every row is built in a list this short, so the evicted ones are
      // too: the selection can't be told apart from them, and goes.
      logs.removeRange(0, 5);
      host.update();
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(host.selectedText, isNull);
      await host.dispose(tester);
    }, variant: macOS);

    testWidgets('evicting the head while following the tail does not throw', (
      tester,
    ) async {
      final logs = makeLogs(200);
      final host = await _Host.pump(tester, logs);
      host.scroll.jumpTo(host.scroll.position.maxScrollExtent);
      await _pumpFrames(tester);
      await _dragSelect(tester, 'Message 180', 'Message 190');
      expect(host.selectedText, isNotNull);

      var next = 200;
      for (var round = 0; round < 15; round++) {
        logs
          ..removeRange(0, 30)
          ..addAll([
            for (var i = 0; i < 30; i++)
              testLogEntry(message: 'Message ${next++}'),
          ]);
        host.update();
        await tester.pump();
        host.scroll.jumpTo(host.scroll.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      await host.dispose(tester);
    }, variant: desktop);

    testWidgets('a click that lands as the list resets does not throw', (
      tester,
    ) async {
      final host = await _Host.pump(tester, makeLogs(40));
      await _dragSelect(tester, 'Message 2', 'Message 9');

      final gesture = await tester.startGesture(
        tester.getCenter(find.textContaining('Message 20').first),
        kind: PointerDeviceKind.mouse,
      );
      host.update(logs: makeLogs(10, prefix: 'Fresh'));
      await tester.pump();
      await gesture.up();
      await _pumpFrames(tester);
      await _click(tester, find.textContaining('Fresh 3').first);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      await host.dispose(tester);
    }, variant: desktop);
  });

  // Clicks, drags, ⌘A and ⇧-arrows interleaved with the list churn above, in
  // a fixed pseudo-random order. Before the fix all but one of these seeds
  // threw, most within a few dozen steps.
  for (var seed = 0; seed < 12; seed++) {
    testWidgets('selection gestures over a churning list (seed $seed)', (
      tester,
    ) async {
      await _churn(tester, seed);
    }, variant: macOS);
  }
}

Future<void> _churn(WidgetTester tester, int seed) async {
  final rnd = Random(seed);
  var next = 0;
  LogEntry entry() => rnd.nextInt(15) == 0
      ? LogEntryUtils.buildSpecial(
          type: LogEntryType.notice,
          message: 'notice ${next++}',
        )
      : testLogEntry(message: 'Message ${next++} ${'x' * rnd.nextInt(40)}');

  final logs = List.generate(80, (_) => entry());
  final host = await _Host.pump(tester, logs, size: const Size(1000, 600));
  final size = tester.getSize(find.byType(LogViewer));
  Offset somewhere() => Offset(
    20 + rnd.nextDouble() * (size.width - 40),
    40 + rnd.nextDouble() * (size.height - 60),
  );
  TestGesture? drag;

  for (var step = 0; step < 120; step++) {
    switch (rnd.nextInt(14)) {
      case 0: // A fresh capture.
        host.update(logs: <LogEntry>[]);
      case 1: // An imported file or a new filter.
        host.update(logs: List.generate(rnd.nextInt(100), (_) => entry()));
      case 2 || 3: // A flush at the buffer cap: append, evict the head.
        final list = host.logs;
        for (var i = rnd.nextInt(30); i > 0; i--) {
          list.add(entry());
        }
        list.removeRange(0, min(list.length, rnd.nextInt(30)));
        host.update();
      case 4: // Auto-follow.
        host.scroll.jumpTo(host.scroll.position.maxScrollExtent);
      case 5:
        host.scroll.jumpTo(
          rnd.nextDouble() * host.scroll.position.maxScrollExtent,
        );
      case 6:
        await tester.tapAt(somewhere(), kind: PointerDeviceKind.mouse);
      case 7:
        await drag?.up();
        drag = await tester.startGesture(
          somewhere(),
          kind: PointerDeviceKind.mouse,
        );
      case 8:
        await drag?.moveTo(somewhere());
      case 9:
        await drag?.up();
        drag = null;
      case 10:
        await _selectAll(tester);
      case 11:
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.tapAt(somewhere(), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      case 12:
        host.update(
          search: TextSearchConfig(
            query: rnd.nextBool() ? 'Message ${rnd.nextInt(9)}' : '',
          ),
        );
      case 13:
        await _withShift(
          tester,
          rnd.nextBool()
              ? LogicalKeyboardKey.arrowDown
              : LogicalKeyboardKey.arrowRight,
        );
    }
    if (rnd.nextBool()) {
      await tester.pump(Duration(milliseconds: rnd.nextInt(40)));
    }
    final error = tester.takeException();
    if (error != null) _failAt(step, error);
  }
  await drag?.up();
  await tester.pump();
  expect(tester.takeException(), isNull);
  await host.dispose(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _click(WidgetTester tester, Finder target) async {
  await tester.tapAt(tester.getCenter(target), kind: PointerDeviceKind.mouse);
  // Past the double-click window, so the next click starts afresh.
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _dragSelect(WidgetTester tester, String from, String to) async {
  final start = tester.getTopLeft(find.textContaining(from).first);
  final end = tester.getBottomRight(find.textContaining(to).first);
  final gesture = await tester.startGesture(
    start + const Offset(2, 4),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(end - const Offset(2, 4));
  await tester.pump();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _selectAll(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await tester.pump();
}

Future<void> _withShift(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pump();
}

/// A [LogViewer] fed the way `LogController` feeds it: one list, often
/// mutated in place, then a rebuild.
class _Host {
  _Host(this.logs);

  final ScrollController scroll = ScrollController();
  List<LogEntry> logs;
  TextSearchConfig search = const TextSearchConfig();
  int? currentMatch;
  String? selectedText;
  bool _shown = true;
  late StateSetter _setState;

  static Future<_Host> pump(
    WidgetTester tester,
    List<LogEntry> logs, {
    Size size = const Size(1200, 800),
  }) async {
    final host = _Host(logs);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              host._setState = setState;
              if (!host._shown) return const SizedBox.shrink();
              return LogViewer(
                logs: host.logs,
                scrollController: host.scroll,
                wrapText: false,
                search: host.search,
                currentMatchLogIndex: host.currentMatch,
                onSelectedTextChanged: (text) => host.selectedText = text,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return host;
  }

  void update({
    List<LogEntry>? logs,
    TextSearchConfig? search,
    int? currentMatch,
  }) {
    _setState(() {
      if (logs != null) this.logs = logs;
      if (search != null) this.search = search;
      if (currentMatch != null) this.currentMatch = currentMatch;
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    _setState(() => _shown = false);
    await tester.pump();
    scroll.dispose();
  }
}

/// Fails with [error] and where it was thrown, which `takeException` drops.
Never _failAt(int step, Object error) {
  final stack = error is Error ? '\n${error.stackTrace}' : '';
  fail('step $step: $error$stack');
}
