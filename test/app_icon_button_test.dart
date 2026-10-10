import 'dart:io';

import 'package:eagly/presentation/components/app_icon_button.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double zoom = 1.0}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(zoom)),
    child: app!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final zoom in [0.8, 1.0, 1.25, 1.8]) {
    testWidgets('centres the icon and fits it at zoom $zoom', (tester) async {
      await tester.pumpWidget(
        _host(
          AppIconButton(icon: Icons.close, tooltip: 'Close', onPressed: () {}),
          zoom: zoom,
        ),
        // The icon's colour tween and the switcher settle quickly.
      );
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(InkWell));
      final glyph = tester.getRect(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      );
      expect(glyph.center.dx, closeTo(box.center.dx, 0.01));
      expect(glyph.center.dy, closeTo(box.center.dy, 0.01));
      // The glyph is laid out at its full zoomed size — never clamped by
      // the box, which is what used to push it right and down.
      expect(glyph.width, closeTo(AppIconButton.defaultIconSize * zoom, 0.01));
      expect(box.contains(glyph.topLeft) && box.contains(glyph.center), isTrue);
    });
  }

  testWidgets('activates from the keyboard and shows a focus ring', (
    tester,
  ) async {
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        AppIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          focusNode: focus,
          onPressed: () => presses++,
        ),
      ),
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    focus.requestFocus();
    await tester.pumpAndSettle();
    final decoration =
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;
    expect((decoration.border! as Border).top.color, isNot(Colors.transparent));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 2);
  });

  testWidgets('a disabled button ignores taps and is not focusable', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(AppIconButton(icon: Icons.close, focusNode: focus)),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.byType(AppIconButton));
  });

  testWidgets('busy swaps the icon for a spinner and ignores taps', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        AppIconButton(
          icon: Icons.refresh,
          busy: true,
          onPressed: () => presses++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    await tester.tap(find.byType(AppIconButton));
    expect(presses, 0);
    // Unmount so the spinner's ticker doesn't outlive the test body.
    await tester.pumpWidget(const SizedBox());
  });

  test('lib/ uses AppIconButton, never a raw IconButton', () {
    final offenders = <String>[];
    final raw = RegExp(r'(?<![A-Za-z_])IconButton(\.[a-z]+)?\(');
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (raw.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use AppIconButton (lib/presentation/components/app_icon_button.dart)'
          ' — Material IconButton misaligns its icon under app zoom.',
    );
  });
}
