import 'dart:io';
import 'dart:math' as math;

import 'package:eagly/presentation/components/feature_view.dart';
import 'package:eagly/presentation/components/overflow_toolbar.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every feature pane wears the same chrome: one [FeatureViewHeader], an
/// optional [FeatureSubBar] and [FeatureStatusBar], inside a [FeaturePane].
/// See "Pane chrome" in AGENTS.md.
void main() {
  group('feature panes use the shared chrome', () {
    // Device home is a scrolling dashboard shown on its own, not a pane in
    // the workspace, so it has no header to share.
    const exempt = {'lib/features/device_home/device_home_feature_view.dart'};

    final views =
        Directory('lib/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('_feature_view.dart'))
            .where((f) => !exempt.contains(f.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('there are feature views to check', () {
      expect(views, isNotEmpty);
    });

    for (final file in views) {
      test('${file.path} builds a FeaturePane', () {
        expect(
          file.readAsStringSync(),
          contains('FeaturePane('),
          reason:
              'Wrap the pane in FeaturePane and give it a FeatureViewHeader '
              'rather than drawing a header of its own.',
        );
      });
    }

    test('no feature draws pane-header pieces itself', () {
      // The workspace itself (home_screen) owns the grip and drag plumbing.
      final pieces = RegExp(
        r'PaneGrip\(|PaneDragArea\(|showsOwnClose|showsOwnTitle|showsGripIn',
      );
      final offenders = [
        for (final file in Directory(
          'lib/features',
        ).listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.dart') &&
              !file.path.startsWith('lib/features/home_screen/') &&
              pieces.hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'Pane headers are FeatureViewHeader; put controls in its '
            'leading / primary / actions / trailing slots.',
      );
    });
  });

  group('FeatureViewHeader', () {
    Future<void> pump(WidgetTester tester, double width, Widget header) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: header),
            ),
          ),
        ),
      );
    }

    ToolbarAction action(IconData icon, String label) =>
        ToolbarAction(icon: icon, label: label, onPressed: () {});

    Widget header({Widget? tabs}) => FeatureViewHeader(
      title: 'Pane',
      tabs: tabs,
      onClose: () {},
      leading: [action(Icons.arrow_back, 'Back')],
      primary: [
        action(Icons.play_arrow, 'Start'),
        action(Icons.pause, 'Pause'),
      ],
      actions: [
        action(Icons.copy, 'Copy'),
        action(Icons.wrap_text, 'Wrap'),
        action(Icons.download, 'Import'),
      ],
    );

    testWidgets('primary controls stay when the actions collapse', (
      tester,
    ) async {
      await pump(tester, 300, header());
      expect(tester.takeException(), isNull);

      for (final icon in [
        Icons.arrow_back,
        Icons.play_arrow,
        Icons.pause,
        Icons.close,
      ]) {
        expect(find.byIcon(icon).hitTestable(), findsOne);
      }
      expect(find.byIcon(Icons.download).hitTestable(), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Import'), findsOne);
      // The menu holds only what collapsed, never a primary control.
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('tabs take the title slot', (tester) async {
      await pump(tester, 800, header(tabs: const Text('tab one')));

      expect(find.text('tab one'), findsOne);
      expect(find.text('Pane'), findsNothing);
    });

    testWidgets('every button shares the header icon size', (tester) async {
      await pump(tester, 800, header());

      final sizes = tester
          .widgetList<Icon>(find.byType(Icon))
          .map(
            (icon) =>
                icon.size ??
                IconTheme.of(tester.element(find.byWidget(icon))).size,
          )
          .toSet();
      expect(sizes, {FeatureViewHeader.iconSize});
    });
  });

  group('fields on pane chrome', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (name, theme) in [
      ('light', AppTheme.lightTheme),
      ('dark', AppTheme.darkTheme),
    ]) {
      test('stand off the bar in the $name theme', () {
        final field = theme.extension<EaglyTheme>()!.chromeFieldColor;
        final bar = theme.colorScheme.surfaceContainerHighest;
        // Not a text-contrast bar: enough of a step that a filled field
        // reads as a box on the bar, which the old fill (the bar's own
        // colour, or one tone off it) did not.
        expect(contrast(field, bar), greaterThanOrEqualTo(1.15));
      });
    }

    testWidgets('a FeatureSubBar fills its text fields with that colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: FeatureSubBar(child: TextField())),
        ),
      );
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      final theme = Theme.of(tester.element(find.byType(InputDecorator)));
      expect(
        decorator.decoration.fillColor ?? theme.inputDecorationTheme.fillColor,
        AppTheme.lightTheme.extension<EaglyTheme>()!.chromeFieldColor,
      );
    });
  });
}
