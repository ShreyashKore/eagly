import 'package:eagly/data/device.dart';
import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_framework.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/data/models/filter_condition.dart';
import 'package:eagly/features/logs/presentation/components/log_filter_controller.dart';
import 'package:eagly/features/logs/services/filter_utils.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _entry({
  required String tag,
  String message = 'hello',
  DevicePlatform platform = DevicePlatform.android,
  LogEntryType type = LogEntryType.log,
}) => LogEntry(
  type: type,
  platform: platform,
  timestamp: '2026-04-26 10:00:00.000',
  pid: '1',
  tid: '1',
  level: 'I',
  tag: tag,
  message: message,
);

LogEntry _ios({required String tag, String message = 'hello'}) =>
    _entry(tag: tag, message: message, platform: DevicePlatform.ios);

LogFilterController _controller({
  List<LogFilters>? emitted,
  bool isIos = false,
}) => LogFilterController(
  initialState: LogFilters.empty(LogLevel.verbose),
  suggestions: LogFilterSuggestions.empty,
  onStateChanged: (state) => emitted?.add(state),
  isIos: isIos,
  debounce: Duration.zero,
);

void main() {
  group('LogFramework.matches', () {
    test('recognises Android Flutter tags', () {
      for (final tag in [
        'flutter',
        'Flutter',
        'FlutterJNI',
        'FlutterEngineCxnRegstry',
        'FlutterLoader',
      ]) {
        expect(
          LogFramework.flutter.matches(_entry(tag: tag)),
          isTrue,
          reason: tag,
        );
      }
      for (final tag in ['ActivityManager', 'ReactNativeJS', 'flutterish']) {
        expect(
          LogFramework.flutter.matches(_entry(tag: tag)),
          isFalse,
          reason: tag,
        );
      }
    });

    test('recognises Android React Native tags', () {
      for (final tag in [
        'ReactNativeJS',
        'ReactNativeJNI',
        'ReactNative',
        'unknown:ReactNative',
        'ReactHost',
      ]) {
        expect(
          LogFramework.reactNative.matches(_entry(tag: tag)),
          isTrue,
          reason: tag,
        );
      }
      for (final tag in ['ActivityManager', 'flutter', 'React']) {
        expect(
          LogFramework.reactNative.matches(_entry(tag: tag)),
          isFalse,
          reason: tag,
        );
      }
    });

    test('recognises iOS Flutter and React Native lines', () {
      expect(LogFramework.flutter.matches(_ios(tag: 'Flutter')), isTrue);
      expect(
        LogFramework.flutter.matches(
          _ios(tag: 'Runner', message: 'flutter: hi'),
        ),
        isTrue,
      );
      expect(LogFramework.flutter.matches(_ios(tag: 'Runner')), isFalse);
      expect(LogFramework.flutter.matches(_ios(tag: 'FlutterJNI')), isFalse);

      for (final tag in ['React', 'React-Core', 'hermes', 'Hermes']) {
        expect(
          LogFramework.reactNative.matches(_ios(tag: tag)),
          isTrue,
          reason: tag,
        );
      }
      expect(LogFramework.reactNative.matches(_ios(tag: 'react')), isFalse);
      expect(LogFramework.reactNative.matches(_ios(tag: 'Flutter')), isFalse);
    });

    test('recognises Android game and hybrid framework tags', () {
      final cases = <LogFramework, (List<String>, List<String>)>{
        LogFramework.unity: (['Unity'], ['UnityAds', 'unity', 'UnityMain']),
        LogFramework.unrealEngine: (['UE', 'UE4', 'UE5'], ['UEFI', 'ue']),
        LogFramework.godot: (
          ['godot', 'GodotLib', 'GodotPlugin', 'Godot'],
          ['godotx', 'Godzilla'],
        ),
        LogFramework.dotnet: (
          ['DOTNET', 'mono', 'mono-stdout', 'mono-rt', 'monodroid-gc'],
          ['monotonic', 'Mono', 'dotnet'],
        ),
        LogFramework.capacitor: (
          ['Capacitor', 'Capacitor/Console', 'Capacitor/Plugin'],
          ['capacitor', 'CapacityManager'],
        ),
        LogFramework.cordova: (
          ['CordovaWebView', 'CordovaActivity', 'CordovaWebViewImpl'],
          ['cordova', 'Cord'],
        ),
        LogFramework.cocos: (
          ['cocos2d-x', 'cocos2d-x debug info', 'CocosCreator', 'Cocos'],
          ['cocos', 'Coco'],
        ),
        LogFramework.gameMaker: (['yoyo'], ['yoyo2', 'Yoyo', 'yo']),
        LogFramework.defold: (['defold'], ['Defold', 'defolder']),
        LogFramework.solar2d: (
          ['Corona'],
          ['corona', 'CoronaVirus', 'Solar2D'],
        ),
        LogFramework.kivy: (
          ['python'],
          ['Python', 'python.stdout', 'python.stderr', 'pythonw'],
        ),
      };
      for (final MapEntry(key: framework, value: (hits, misses))
          in cases.entries) {
        for (final tag in hits) {
          expect(
            framework.matches(_entry(tag: tag)),
            isTrue,
            reason: '$framework $tag',
          );
          // No other framework claims the line.
          for (final other in LogFramework.values) {
            if (other == framework) continue;
            expect(
              other.matches(_entry(tag: tag)),
              isFalse,
              reason: '$other $tag',
            );
          }
        }
        for (final tag in misses) {
          expect(
            framework.matches(_entry(tag: tag)),
            isFalse,
            reason: '$framework $tag',
          );
        }
      }
    });

    test('recognises iOS dynamic-framework images only', () {
      expect(LogFramework.unity.matches(_ios(tag: 'UnityFramework')), isTrue);
      expect(LogFramework.unity.matches(_ios(tag: 'Unity')), isFalse);
      expect(LogFramework.capacitor.matches(_ios(tag: 'Capacitor')), isTrue);
      expect(LogFramework.cordova.matches(_ios(tag: 'Cordova')), isTrue);
      expect(LogFramework.cordova.matches(_ios(tag: 'CordovaLib')), isTrue);
      expect(
        LogFramework.cordova.matches(_ios(tag: 'CordovaWebView')),
        isFalse,
      );
      // Statically linked on iOS: nothing to recognise them by.
      for (final (framework, tag) in [
        (LogFramework.unrealEngine, 'UE'),
        (LogFramework.godot, 'godot'),
        (LogFramework.dotnet, 'DOTNET'),
        (LogFramework.cocos, 'cocos2d-x'),
        (LogFramework.gameMaker, 'yoyo'),
        (LogFramework.defold, 'defold'),
        (LogFramework.solar2d, 'Corona'),
        (LogFramework.kivy, 'python'),
      ]) {
        expect(framework.matches(_ios(tag: tag)), isFalse, reason: tag);
      }
    });

    test('every framework with a logo has its own under the directory', () {
      // No official SVG to copy for these; the chip draws a glyph.
      const withoutLogo = {LogFramework.solar2d, LogFramework.kivy};
      final logos = <String>[];
      for (final framework in LogFramework.values) {
        final asset = framework.logoAsset;
        if (withoutLogo.contains(framework)) {
          expect(asset, isNull, reason: '$framework');
          continue;
        }
        expect(asset, startsWith('${LogFramework.logoDirectory}/'));
        expect(asset, endsWith('.svg'));
        logos.add(asset!);
      }
      expect(logos.toSet(), hasLength(logos.length));
      // Only Defold's logo is full colour; the Simple Icons glyphs are tinted.
      expect(LogFramework.values.where((f) => f.logoHasOwnColours), [
        LogFramework.defold,
      ]);
    });

    test('special entries never match', () {
      for (final framework in LogFramework.values) {
        expect(
          framework.matches(_entry(tag: 'flutter', type: LogEntryType.started)),
          isFalse,
        );
        expect(
          framework.matches(
            _entry(tag: 'ReactNativeJS', type: LogEntryType.notice),
          ),
          isFalse,
        );
      }
    });

    test('fromToken accepts aliases', () {
      expect(LogFramework.fromToken('Flutter'), LogFramework.flutter);
      for (final alias in [
        'react-native',
        'ReactNative',
        'react_native',
        'RN',
      ]) {
        expect(LogFramework.fromToken(alias), LogFramework.reactNative);
      }
      final aliases = <LogFramework, List<String>>{
        LogFramework.unity: ['unity', 'Unity'],
        LogFramework.unrealEngine: [
          'unreal',
          'UnrealEngine',
          'unreal-engine',
          'ue',
          'UE4',
          'ue5',
        ],
        LogFramework.godot: ['godot'],
        LogFramework.dotnet: ['dotnet', '.NET', 'maui', 'Xamarin'],
        LogFramework.capacitor: ['capacitor', 'ionic'],
        LogFramework.cordova: ['cordova', 'PhoneGap'],
        LogFramework.cocos: ['cocos', 'cocos2d', 'cocos2d-x', 'CocosCreator'],
        LogFramework.gameMaker: ['gamemaker', 'GMS', 'yoyo'],
        LogFramework.defold: ['defold', 'Defold'],
        LogFramework.solar2d: ['solar2d', 'Solar2D', 'corona'],
        LogFramework.kivy: ['kivy', 'Kivy', 'python-for-android', 'p4a'],
      };
      for (final MapEntry(key: framework, value: values) in aliases.entries) {
        for (final alias in values) {
          expect(LogFramework.fromToken(alias), framework, reason: alias);
        }
      }
      // Every framework's own token names it.
      for (final framework in LogFramework.values) {
        expect(LogFramework.fromToken(framework.token), framework);
      }
      expect(LogFramework.fromToken('swiftui'), isNull);
    });
  });

  group('framework filters in LogFilters', () {
    LogFilters parse(String text) => LogFilters.parse(
      text,
      fallbackLevel: LogLevel.verbose,
      isIosLogContext: false,
    );

    String compose(LogFilters filters) => LogFilters.compose(
      filters,
      defaultLevel: LogLevel.verbose,
      isIos: false,
    );

    test('parse and compose round-trip', () {
      final parsed = parse('framework:flutter -framework:rn');
      expect(parsed.frameworks, {LogFramework.flutter});
      expect(parsed.excludedFrameworks, {LogFramework.reactNative});
      expect(parsed.rawTerms, isEmpty);

      final composed = compose(parsed);
      expect(composed, 'framework:flutter -framework:react-native');
      final reparsed = parse(composed);
      expect(reparsed.frameworks, parsed.frameworks);
      expect(reparsed.excludedFrameworks, parsed.excludedFrameworks);
    });

    test('game framework tokens round-trip', () {
      final parsed = parse('framework:unity -framework:godot');
      expect(parsed.frameworks, {LogFramework.unity});
      expect(parsed.excludedFrameworks, {LogFramework.godot});
      final composed = compose(parsed);
      expect(composed, 'framework:unity -framework:godot');
      final reparsed = parse('framework:ue5 -framework:maui');
      expect(reparsed.frameworks, {LogFramework.unrealEngine});
      expect(reparsed.excludedFrameworks, {LogFramework.dotnet});
      expect(compose(reparsed), 'framework:unreal -framework:dotnet');
    });

    test('a later token moves a framework between the sets', () {
      final parsed = parse('framework:flutter -fw:flutter');
      expect(parsed.frameworks, isEmpty);
      expect(parsed.excludedFrameworks, {LogFramework.flutter});
    });

    test('an unknown framework value is ignored', () {
      final parsed = parse('framework:swiftui');
      expect(parsed.frameworks, isEmpty);
      expect(parsed.excludedFrameworks, isEmpty);
      expect(parsed.rawTerms, isEmpty);
      expect(compose(parsed), '');
    });

    test('matching includes or excludes, ANDed with other terms', () {
      final flutterAuth = _entry(tag: 'flutter', message: 'auth ok');
      final flutterOther = _entry(tag: 'flutter', message: 'frame');
      final native = _entry(tag: 'AuthService', message: 'auth ok');

      bool matches(LogEntry entry, String text) =>
          matchesLogFilters(entry, parse(text), LogLevel.verbose);

      expect(matches(flutterAuth, 'framework:flutter'), isTrue);
      expect(matches(native, 'framework:flutter'), isFalse);
      expect(matches(flutterAuth, '-framework:flutter'), isFalse);
      expect(matches(native, '-framework:flutter'), isTrue);

      expect(matches(flutterAuth, 'framework:flutter message:auth'), isTrue);
      expect(matches(flutterOther, 'framework:flutter message:auth'), isFalse);
      expect(matches(native, 'framework:flutter message:auth'), isFalse);
      expect(matches(native, '-framework:flutter tag:Auth'), isTrue);
      expect(matches(flutterAuth, '-framework:rn tag:flutter'), isTrue);
    });
  });

  group('LogFilterController framework filters', () {
    test('setFrameworkMode emits at once and can clear', () {
      final emitted = <LogFilters>[];
      final controller = _controller(emitted: emitted);
      addTearDown(controller.dispose);

      controller.setFrameworkMode(
        LogFramework.flutter,
        FrameworkFilterMode.only,
      );
      expect(emitted.last.frameworks, {LogFramework.flutter});
      expect(
        controller.frameworkMode(LogFramework.flutter),
        FrameworkFilterMode.only,
      );
      expect(controller.activeFilterCount, 1);

      controller.setFrameworkMode(
        LogFramework.flutter,
        FrameworkFilterMode.hide,
      );
      expect(emitted.last.frameworks, isEmpty);
      expect(emitted.last.excludedFrameworks, {LogFramework.flutter});

      controller.setFrameworkMode(LogFramework.flutter, null);
      expect(emitted.last.excludedFrameworks, isEmpty);
      expect(controller.frameworkMode(LogFramework.flutter), isNull);
    });

    test('pill edits keep framework filters; clearing removes them', () {
      final emitted = <LogFilters>[];
      final controller = _controller(emitted: emitted);
      addTearDown(controller.dispose);

      controller.setFrameworkMode(
        LogFramework.flutter,
        FrameworkFilterMode.only,
      );
      controller.setFrameworkMode(
        LogFramework.reactNative,
        FrameworkFilterMode.hide,
      );

      controller.addConditionWithValue(FilterConditionField.tag, 'Auth');
      expect(emitted.last.tagTerms, hasLength(1));
      expect(emitted.last.frameworks, {LogFramework.flutter});
      expect(emitted.last.excludedFrameworks, {LogFramework.reactNative});

      final id = controller.conditions.single.id;
      controller.updateCondition(id, operator: FilterOperator.notContains);
      expect(emitted.last.frameworks, {LogFramework.flutter});

      controller.removeCondition(id);
      expect(emitted.last.tagTerms, isEmpty);
      expect(emitted.last.frameworks, {LogFramework.flutter});
      expect(emitted.last.excludedFrameworks, {LogFramework.reactNative});

      controller.setMaxAge(const Duration(minutes: 5));
      expect(emitted.last.frameworks, {LogFramework.flutter});

      controller.clearConditions();
      expect(emitted.last.frameworks, isEmpty);
      expect(emitted.last.excludedFrameworks, isEmpty);
      expect(controller.activeFilterCount, 0);
    });

    test('typed framework tokens set the framework modes', () {
      final emitted = <LogFilters>[];
      final controller = _controller(emitted: emitted);
      addTearDown(controller.dispose);

      controller.applyTyped('framework:flutter tag:Auth');
      expect(emitted.last.frameworks, {LogFramework.flutter});
      expect(controller.conditions, hasLength(1));

      controller.applyTyped('-framework:flutter');
      expect(emitted.last.frameworks, isEmpty);
      expect(emitted.last.excludedFrameworks, {LogFramework.flutter});
      expect(emitted.last.tagTerms, hasLength(1));
    });

    test('updateDetectedFrameworks notifies only on change', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.updateDetectedFrameworks({LogFramework.flutter});
      controller.updateDetectedFrameworks({LogFramework.flutter});
      expect(notifications, 1);
      expect(controller.visibleFrameworks, [LogFramework.flutter]);

      controller.updateDetectedFrameworks(const {});
      expect(notifications, 2);
      expect(controller.visibleFrameworks, isEmpty);
    });

    test(
      'visibleFrameworks keeps a filtered framework that is not detected',
      () {
        final controller = _controller();
        addTearDown(controller.dispose);

        controller.updateDetectedFrameworks({LogFramework.flutter});
        controller.setFrameworkMode(
          LogFramework.reactNative,
          FrameworkFilterMode.hide,
        );
        expect(controller.visibleFrameworks, [
          LogFramework.flutter,
          LogFramework.reactNative,
        ]);

        controller.updateDetectedFrameworks(const {});
        expect(controller.visibleFrameworks, [LogFramework.reactNative]);
      },
    );
  });
}
