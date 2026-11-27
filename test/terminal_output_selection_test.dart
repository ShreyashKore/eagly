import 'dart:math';

import 'package:eagly/features/terminal/components/terminal_output_view.dart';
import 'package:eagly/features/terminal/data/terminal_line.dart';
import 'package:eagly/features/terminal/terminal_find.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Text selection over the terminal scrollback, which streams (`adb logcat`),
/// drops its head at a cap and is cleared, under a `SelectionArea` — the same
/// shape as the log viewer, and the same Flutter selection crashes (Sentry
/// FLUTTER-B, -E, -4A, -A3); see log_viewer_selection_test.dart.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  List<TerminalLine> makeLines(int count, {String prefix = 'line'}) => [
    for (var i = 0; i < count; i++)
      TerminalLine(TerminalLineKind.stdout, '$prefix $i'),
  ];

  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⇧↓ after the selection scrolled away does not throw', (
    tester,
  ) async {
    final host = await _Host.pump(tester, makeLines(400));
    final scroll = host.scrollController(tester);
    scroll.jumpTo(0);
    await tester.pump();
    await _dragSelect(tester, 'line 3', 'line 6');
    scroll.jumpTo(4000);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(tester.takeException(), isNull);
  }, variant: macOS);

  testWidgets('⌘A after a click scrolled away does not throw', (tester) async {
    final host = await _Host.pump(tester, makeLines(400));
    final scroll = host.scrollController(tester);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.textContaining('line 12').first),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(tester.takeException(), isNull);
  }, variant: macOS);

  // Streaming at the scrollback cap, `clear`, clicks and drags in between.
  for (var seed = 0; seed < 8; seed++) {
    testWidgets('selection gestures over a streaming scrollback (seed $seed)', (
      tester,
    ) async {
      final rnd = Random(seed);
      var next = 0;
      TerminalLine line() =>
          TerminalLine(TerminalLineKind.stdout, 'out ${next++}');
      var lines = [for (var i = 0; i < 120; i++) line()];
      final host = await _Host.pump(tester, lines);
      final size = tester.getSize(find.byType(TerminalOutputView));
      Offset somewhere() => Offset(
        20 + rnd.nextDouble() * (size.width - 40),
        20 + rnd.nextDouble() * (size.height - 40),
      );
      TestGesture? drag;

      for (var step = 0; step < 100; step++) {
        switch (rnd.nextInt(10)) {
          case 0: // `clear`.
            lines = [];
          case 1 || 2 || 3: // Output at the cap: append, drop the head.
            lines = [
              ...lines.skip(min(lines.length, rnd.nextInt(40))),
              for (var i = rnd.nextInt(40); i > 0; i--) line(),
            ];
          case 4:
            await tester.tapAt(somewhere(), kind: PointerDeviceKind.mouse);
          case 5:
            await drag?.up();
            drag = await tester.startGesture(
              somewhere(),
              kind: PointerDeviceKind.mouse,
            );
          case 6:
            await drag?.moveTo(somewhere());
          case 7:
            await drag?.up();
            drag = null;
          case 8:
            final scroll = host.scrollController(tester);
            scroll.jumpTo(rnd.nextDouble() * scroll.position.maxScrollExtent);
          case 9:
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        }
        // The view gets a fresh copy each time, as `TerminalController.lines`
        // hands out. Output is flushed to it every 60 ms, so the frame that
        // lands a stuck-to-bottom view on its tail (a post-frame jump) is
        // over before the next change — the list's jump estimate goes stale
        // if the list empties first, a super_sliver_list assert unrelated to
        // selection.
        host.update(List.unmodifiable(lines));
        await tester.pump(Duration(milliseconds: rnd.nextInt(40)));
        await tester.pump();
        final error = tester.takeException();
        if (error != null) _failAt(step, error);
      }
      await drag?.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }, variant: macOS);
  }
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

class _Host {
  _Host(this.lines);

  List<TerminalLine> lines;
  late final TerminalFind terminalFind = TerminalFind(() => lines);
  late StateSetter _setState;

  ScrollController scrollController(WidgetTester tester) => tester
      .widget<Scrollable>(
        find.descendant(
          of: find.byType(TerminalOutputView),
          matching: find.byType(Scrollable),
        ),
      )
      .controller!;

  static Future<_Host> pump(
    WidgetTester tester,
    List<TerminalLine> lines,
  ) async {
    final host = _Host(lines);
    addTearDown(host.terminalFind.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              host._setState = setState;
              return TerminalOutputView(
                lines: host.lines,
                find: host.terminalFind,
                fontSize: 12,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return host;
  }

  void update(List<TerminalLine> next) {
    _setState(() => lines = next);
    terminalFind.refresh();
  }
}

/// Fails with [error] and where it was thrown, which `takeException` drops.
Never _failAt(int step, Object error) {
  final stack = error is Error ? '\n${error.stackTrace}' : '';
  fail('step $step: $error$stack');
}
