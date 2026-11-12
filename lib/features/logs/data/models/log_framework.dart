import '../../../../data/device.dart';
import 'log_entry.dart';

/// An app or game framework whose log lines the Logs pane can recognise, so
/// they can be isolated or hidden with one click (`framework:` in typed filter
/// syntax).
///
/// Recognition is a heuristic on [LogEntry.tag], whose meaning depends on the
/// platform:
/// - **Android:** the logcat tag the code logged under.
/// - **iOS:** the image (library) name the iOS parser takes from the last
///   parenthesised part of the process label, so `Runner(Flutter)` gives tag
///   `Flutter` and package `Runner` (see `IosSyslogParser`'s `build()`). Only
///   a framework shipped as a *dynamic* image shows up there; one linked
///   statically into the app logs under the app's own image and can't be told
///   apart (see [matches]).
enum LogFramework(
  /// The name shown on the framework's chip.
  final String label,

  /// The value used in typed filter syntax (`framework:<token>`).
  final String token,

  /// The logo's file name under [logoDirectory], or null for a framework
  /// with no official mark available.
  final String? _logoFile,
) {
  flutter('Flutter', 'flutter', 'flutter.svg'),
  reactNative('React Native', 'react-native', 'react.svg'),
  unity('Unity', 'unity', 'unity.svg'),
  unrealEngine('Unreal Engine', 'unreal', 'unrealengine.svg'),
  godot('Godot', 'godot', 'godotengine.svg'),
  dotnet('.NET', 'dotnet', 'dotnet.svg'),
  capacitor('Capacitor', 'capacitor', 'capacitor.svg'),
  cordova('Cordova', 'cordova', 'apachecordova.svg'),
  cocos('Cocos', 'cocos', 'cocos.svg'),
  gameMaker('GameMaker', 'gamemaker', 'gamemaker.svg'),
  defold('Defold', 'defold', 'defold.svg'),
  solar2d('Solar2D', 'solar2d', null),
  kivy('Kivy', 'kivy', null);

  /// Where the framework logos live (official marks; see the README there for
  /// sources and attribution).
  static const String logoDirectory = 'assets/logos/frameworks';

  /// The asset path of the framework's official logo, or null when none is
  /// available (Solar2D, Kivy) and the chip draws a generic glyph instead.
  /// Most are monochrome 24×24 Simple Icons glyphs meant to be tinted; see
  /// [logoHasOwnColours] for the exception.
  String? get logoAsset {
    final file = _logoFile;
    return file == null ? null : '$logoDirectory/$file';
  }

  /// Whether [logoAsset] is a full-colour mark that must be drawn as is.
  /// Defold's logo is the project's own gradient artwork, whose pieces tile
  /// each other: tinting it one colour would flatten it to a silhouette.
  bool get logoHasOwnColours => this == LogFramework.defold;

  /// The framework typed filter syntax names by [value] (case-insensitive,
  /// with a few aliases), or null when it names none.
  static LogFramework? fromToken(String value) => switch (value
      .trim()
      .toLowerCase()) {
    'flutter' => LogFramework.flutter,
    'react-native' ||
    'reactnative' ||
    'react_native' ||
    'rn' => LogFramework.reactNative,
    'unity' => LogFramework.unity,
    'unreal' ||
    'unrealengine' ||
    'unreal-engine' ||
    'ue' ||
    'ue4' ||
    'ue5' => LogFramework.unrealEngine,
    'godot' => LogFramework.godot,
    'dotnet' || '.net' || 'maui' || 'xamarin' => LogFramework.dotnet,
    'capacitor' || 'ionic' => LogFramework.capacitor,
    'cordova' || 'phonegap' => LogFramework.cordova,
    'cocos' || 'cocos2d' || 'cocos2d-x' || 'cocoscreator' => LogFramework.cocos,
    'gamemaker' || 'gms' || 'yoyo' => LogFramework.gameMaker,
    'defold' => LogFramework.defold,
    'solar2d' || 'corona' => LogFramework.solar2d,
    'kivy' || 'python-for-android' || 'p4a' => LogFramework.kivy,
    _ => null,
  };

  /// The iOS images React Native logs from (case-sensitive).
  static const Set<String> _iosReactNativeImages = {
    'React',
    'React-Core',
    'React_Core',
    'hermes',
    'Hermes',
  };

  /// Whether [entry] is one of this framework's log lines. Special (status)
  /// entries never match. Plain string compares only, since this runs for
  /// every entry of a filtered view.
  bool matches(LogEntry entry) {
    if (entry.type != LogEntryType.log) return false;
    return switch (entry.platform) {
      DevicePlatform.android => _matchesAndroid(entry.tag),
      DevicePlatform.ios => _matchesIos(entry),
    };
  }

  /// The logcat tags each framework logs under:
  /// - Flutter: `flutter` (any case, where `print` goes) or a tag starting
  ///   `Flutter` (FlutterJNI, FlutterEngine…, FlutterLoader).
  /// - React Native: a tag starting `ReactNative` (ReactNativeJS,
  ///   ReactNativeJNI), `unknown:ReactNative`, or `ReactHost`.
  /// - Unity: `Unity` (`Debug.Log`).
  /// - Unreal Engine: `UE` (UE5), `UE4` or `UE5`.
  /// - Godot: `godot` (the engine) or a Java tag starting `Godot`.
  /// - .NET (MAUI, Xamarin): `DOTNET` (console output, .NET 6+), `mono`,
  ///   `mono-stdout`, `mono-rt`, or a tag starting `monodroid`.
  /// - Capacitor: a tag starting `Capacitor` (`Capacitor/Console`…).
  /// - Cordova: a tag starting `Cordova` (CordovaWebView, CordovaActivity…).
  /// - Cocos: a tag starting `cocos2d` (cocos2d-x) or `Cocos` (Cocos Creator).
  /// - GameMaker: `yoyo`.
  /// - Defold: `defold` (the engine and Lua `print`).
  /// - Solar2D (formerly Corona SDK): `Corona` (the engine and Lua `print`).
  /// - Kivy: `python`, where python-for-android sends the app's stdout and
  ///   Kivy's own logger (`[INFO   ] [Kivy  ] …`). Another python-for-android
  ///   app logs there too, but nearly all of them are Kivy apps. Chaquopy
  ///   (BeeWare) uses `python.stdout` / `python.stderr` and is not claimed.
  ///
  /// NativeScript is left out: it logs under `JS`, which other runtimes use
  /// too, so the tag alone would mislabel their lines.
  bool _matchesAndroid(String tag) => switch (this) {
    LogFramework.flutter =>
      tag.startsWith('Flutter') || tag.toLowerCase() == 'flutter',
    LogFramework.reactNative =>
      tag.startsWith('ReactNative') ||
          tag == 'unknown:ReactNative' ||
          tag == 'ReactHost',
    LogFramework.unity => tag == 'Unity',
    LogFramework.unrealEngine => tag == 'UE' || tag == 'UE4' || tag == 'UE5',
    LogFramework.godot => tag == 'godot' || tag.startsWith('Godot'),
    LogFramework.dotnet =>
      tag == 'DOTNET' ||
          tag == 'mono' ||
          tag == 'mono-stdout' ||
          tag == 'mono-rt' ||
          tag.startsWith('monodroid'),
    LogFramework.capacitor => tag.startsWith('Capacitor'),
    LogFramework.cordova => tag.startsWith('Cordova'),
    LogFramework.cocos => tag.startsWith('cocos2d') || tag.startsWith('Cocos'),
    LogFramework.gameMaker => tag == 'yoyo',
    LogFramework.defold => tag == 'defold',
    LogFramework.solar2d => tag == 'Corona',
    LogFramework.kivy => tag == 'python',
  };

  /// The iOS images each framework logs from:
  /// - Flutter: the `Flutter` image, or a message starting `flutter: `
  ///   (`print` from the app's own image).
  /// - React Native: one of the React / Hermes images. That needs React built
  ///   as dynamic frameworks: by default it is linked statically, and `RCTLog`
  ///   writes plain messages to the os_log subsystem `com.facebook.react.log`,
  ///   which Eagly's iOS relay does not carry. So most iOS React Native apps
  ///   go unrecognised.
  /// - Unity: `UnityFramework`.
  /// - Capacitor: `Capacitor`.
  /// - Cordova: `Cordova` or `CordovaLib`.
  /// - Unreal Engine, Godot, .NET, Cocos, GameMaker, Defold, Solar2D and Kivy
  ///   (kivy-ios) link statically into the app on iOS, leaving nothing to
  ///   recognise them by.
  bool _matchesIos(LogEntry entry) {
    final tag = entry.tag;
    return switch (this) {
      LogFramework.flutter =>
        tag == 'Flutter' || entry.message.startsWith('flutter: '),
      LogFramework.reactNative => _iosReactNativeImages.contains(tag),
      LogFramework.unity => tag == 'UnityFramework',
      LogFramework.capacitor => tag == 'Capacitor',
      LogFramework.cordova => tag == 'Cordova' || tag == 'CordovaLib',
      LogFramework.unrealEngine ||
      LogFramework.godot ||
      LogFramework.dotnet ||
      LogFramework.cocos ||
      LogFramework.gameMaker ||
      LogFramework.defold ||
      LogFramework.solar2d ||
      LogFramework.kivy => false,
    };
  }
}

/// How a framework filter treats its framework's lines.
enum FrameworkFilterMode {
  /// Show only this framework's lines.
  only,

  /// Hide this framework's lines.
  hide,
}
