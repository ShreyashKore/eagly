import 'dart:io';

import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_framework.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/presentation/components/log_filter_controller.dart';
import 'package:eagly/features/logs/presentation/components/log_framework_chips.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  LogFilterController buildController() => LogFilterController(
    initialState: LogFilters.empty(LogLevel.verbose),
    suggestions: LogFilterSuggestions.empty,
    onStateChanged: (_) {},
    isIos: false,
  );

  Future<void> pumpChips(
    WidgetTester tester,
    LogFilterController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(child: LogFrameworkChips(controller: controller)),
        ),
      ),
    );
  }

  testWidgets('renders nothing until a framework is detected', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await pumpChips(tester, controller);

    expect(find.text('Flutter'), findsNothing);
    expect(find.byType(SvgPicture), findsNothing);
    expect(tester.getSize(find.byType(LogFrameworkChips)), Size.zero);

    controller.updateDetectedFrameworks({LogFramework.flutter});
    await tester.pump();
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('React Native'), findsNothing);

    // The chip is drawn in the framework's accent, not the pill colours,
    // with its official logo tinted to match.
    final label = tester.widget<Text>(find.text('Flutter'));
    final theme = AppTheme.lightTheme.extension<EaglyTheme>()!;
    final accent = theme.frameworkColor(LogFramework.flutter);
    expect(label.style?.color, accent);
    final logo = tester.widget<FrameworkLogo>(find.byType(FrameworkLogo));
    expect(logo.framework, LogFramework.flutter);
    expect(logo.color, accent);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('every detected framework gets its own logo', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    tester.view
      ..physicalSize = const Size(2400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.updateDetectedFrameworks(LogFramework.values.toSet());
    await pumpChips(tester, controller);

    final withLogo = LogFramework.values.where((f) => f.logoAsset != null);
    expect(find.byType(SvgPicture), findsNWidgets(withLogo.length));
    // The rest draw a glyph of their own in the logo's place, so two compact
    // chips still differ by shape.
    final glyphs = [
      for (final framework in LogFramework.values)
        if (framework.logoAsset == null) FrameworkLogo.fallbackIcon(framework),
    ];
    expect(glyphs, isNot(contains(null)));
    expect(glyphs.toSet(), hasLength(glyphs.length));
    for (final glyph in glyphs) {
      expect(find.byIcon(glyph!), findsOneWidget);
    }
    final logos = tester
        .widgetList<FrameworkLogo>(find.byType(FrameworkLogo))
        .map((logo) => logo.framework);
    expect(logos, LogFramework.values);
    // Past two frameworks the chips show their logos only.
    for (final framework in LogFramework.values) {
      expect(find.text(framework.label), findsNothing);
    }
  });

  testWidgets('a third framework slides the labels away, not snapping', (
    tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    controller.updateDetectedFrameworks({
      LogFramework.flutter,
      LogFramework.unity,
    });
    await pumpChips(tester, controller);
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('Unity'), findsOneWidget);
    double chipWidth() =>
        tester.getSize(find.byKey(const ValueKey(LogFramework.flutter))).width;
    final labelled = chipWidth();

    controller.updateDetectedFrameworks({
      LogFramework.flutter,
      LogFramework.unity,
      LogFramework.godot,
    });
    await tester.pump();
    await tester.pump(LogFrameworkChips.labelMotion ~/ 2);
    final midway = chipWidth();
    expect(find.text('Flutter'), findsOneWidget, reason: 'still sliding out');
    await tester.pump(LogFrameworkChips.labelMotion);
    final logoOnly = chipWidth();
    expect(find.text('Flutter'), findsNothing);
    expect(find.text('Godot'), findsNothing);
    expect(midway, lessThan(labelled));
    expect(midway, greaterThan(logoOnly));
    // The tooltip names the framework once the label is gone.
    expect(
      tester.widgetList<Tooltip>(find.byType(Tooltip)).first.message,
      startsWith('Flutter: '),
    );

    // Back to two: the labels slide back in.
    controller.updateDetectedFrameworks({
      LogFramework.flutter,
      LogFramework.unity,
    });
    await tester.pump();
    await tester.pump(LogFrameworkChips.labelMotion ~/ 2);
    expect(chipWidth(), allOf(greaterThan(logoOnly), lessThan(labelled)));
    await tester.pump(LogFrameworkChips.labelMotion);
    expect(chipWidth(), labelled);
  });

  testWidgets('with reduced motion the labels switch at once', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    controller.updateDetectedFrameworks({LogFramework.flutter});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(child: LogFrameworkChips(controller: controller)),
          ),
        ),
      ),
    );
    controller.updateDetectedFrameworks({
      LogFramework.flutter,
      LogFramework.unity,
      LogFramework.godot,
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('Flutter'), findsNothing);
  });

  testWidgets('a click shows only the framework; the menu hides and clears', (
    tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    controller.updateDetectedFrameworks({LogFramework.flutter});
    await pumpChips(tester, controller);

    await tester.tap(find.text('Flutter'));
    await tester.pump();
    expect(
      controller.frameworkMode(LogFramework.flutter),
      FrameworkFilterMode.only,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Flutter'));
    await tester.pump();
    expect(controller.frameworkMode(LogFramework.flutter), isNull);

    await tester.tap(find.text('Flutter'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide Flutter logs'));
    await tester.pumpAndSettle();
    expect(
      controller.frameworkMode(LogFramework.flutter),
      FrameworkFilterMode.hide,
    );
    // A hidden chip keeps its logo, struck through, so two hidden compact
    // chips still differ.
    expect(find.byIcon(Icons.visibility_off), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(
      tester.widget<FrameworkLogo>(find.byType(FrameworkLogo)).struckThrough,
      isTrue,
    );
    final label = tester.widget<Text>(find.text('Flutter'));
    expect(label.style?.decoration, TextDecoration.lineThrough);

    await tester.tap(find.text('Flutter'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Flutter filter'));
    await tester.pumpAndSettle();
    expect(controller.frameworkMode(LogFramework.flutter), isNull);
  });

  group('Defold full-colour logo', () {
    /// The opaque pixels of the Defold logo rendered at its own size.
    Future<List<Color>> renderDefold(WidgetTester tester) async {
      final svg = File(LogFramework.defold.logoAsset!).readAsStringSync();
      final pixels = await tester.runAsync(() async {
        final info = await vg.loadPicture(
          SvgStringLoader(inlineSvgClassStyles(svg)),
          null,
        );
        final image = await info.picture.toImage(
          info.size.width.ceil(),
          info.size.height.ceil(),
        );
        info.picture.dispose();
        final data = await image.toByteData();
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        return [
          for (var i = 0; i < bytes.length; i += 4)
            if (bytes[i + 3] > 250)
              Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]),
        ];
      });
      return pixels!;
    }

    testWidgets('its <style> classes are inlined so it paints in colour', (
      tester,
    ) async {
      final svg = File(LogFramework.defold.logoAsset!).readAsStringSync();
      final inlined = inlineSvgClassStyles(svg);
      expect(inlined, isNot(contains('<style')));
      expect(inlined, isNot(contains('class=')));
      expect(inlined, contains('style="fill:#15244A;"'));
      expect(inlined, contains('style="fill:url(#SVGID_1_);"'));

      final pixels = await renderDefold(tester);
      expect(pixels, isNotEmpty);
      // flutter_svg ignores <style>, so without inlining every piece is
      // black. Each of the three fills must show: the navy, the blue-to-cyan
      // gradient and the red-to-yellow gradient.
      bool any(bool Function(Color c) test) => pixels.any(test);
      int channel(double v) => (v * 255).round();
      expect(any((c) => c == const Color(0xFF15244A)), isTrue, reason: 'navy');
      expect(
        any((c) => channel(c.b) > 200 && channel(c.r) < 80),
        isTrue,
        reason: 'blue-cyan gradient',
      );
      expect(
        any((c) => channel(c.r) > 220 && channel(c.b) < 80),
        isTrue,
        reason: 'red-yellow gradient',
      );
      expect(pixels.every((c) => c == const Color(0xFF000000)), isFalse);
    });

    testWidgets('the chip draws it untinted, and dimmed when hidden', (
      tester,
    ) async {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.updateDetectedFrameworks({LogFramework.defold});
      await pumpChips(tester, controller);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      SvgPicture picture() =>
          tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(picture().colorFilter, isNull);
      // Loaded and painting a picture, not an empty placeholder.
      expect(
        find.descendant(
          of: find.byType(SvgPicture),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_RawPictureVectorGraphicWidget',
          ),
        ),
        findsOneWidget,
      );

      controller.setFrameworkMode(
        LogFramework.defold,
        FrameworkFilterMode.hide,
      );
      await tester.pump();
      // dstIn scales the logo's alpha and keeps its colours.
      expect(
        picture().colorFilter,
        ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.dstIn),
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('inlineSvgClassStyles leaves an SVG without <style> alone', () {
    const svg = '<svg><path class="a" d="M0 0h1v1z"/></svg>';
    expect(inlineSvgClassStyles(svg), svg);
  });
}
