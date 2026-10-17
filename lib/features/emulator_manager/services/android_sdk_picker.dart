import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../services/preferences_service.dart';
import '../../../utils/android_sdk_path.dart';

/// The verdict on a directory the user offered as their Android SDK root.
@immutable
class AndroidSdkChoice {
  const AndroidSdkChoice({
    required this.path,
    required this.accepted,
    required this.message,
  });

  final String path;

  /// False when the directory holds nothing an SDK would hold. Saving one of
  /// those breaks the emulator manager silently — the list just stays empty —
  /// so it is refused at the point the user can still fix it.
  final bool accepted;

  /// What to tell the user, whether or not it was accepted.
  final String message;
}

/// Points Eagly at an Android SDK and remembers where.
///
/// The override exists because the environment usually cannot be trusted: an
/// app launched from Finder or the Start menu inherits the login environment
/// rather than a shell's, so `ANDROID_HOME` is typically unset even on a
/// machine where Android Studio works fine. See [AndroidSdkPath].
class AndroidSdkPicker {
  const AndroidSdkPicker._();

  /// Opens the directory picker. Swappable because a file picker needs a
  /// platform channel, and the decision either side of it is worth testing.
  @visibleForTesting
  static Future<String?> Function({String? initialDirectory}) chooseDirectory =
      _chooseWithFilePicker;

  @visibleForTesting
  static void resetChooseDirectory() {
    chooseDirectory = _chooseWithFilePicker;
  }

  static Future<String?> _chooseWithFilePicker({String? initialDirectory}) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose your Android SDK folder',
      initialDirectory: initialDirectory,
    );
  }

  /// Asks for a directory, judges it, and saves it when it holds up.
  ///
  /// Returns `null` when the user cancelled — which is not the same as a
  /// rejected choice and should say nothing.
  static Future<AndroidSdkChoice?> chooseAndSave({
    String? initialDirectory,
  }) async {
    final chosen = await chooseDirectory(initialDirectory: initialDirectory);
    final path = chosen?.trim();
    if (path == null || path.isEmpty) return null;

    final choice = evaluate(path);
    if (choice.accepted) {
      await PreferencesService.setAndroidSdkPath(choice.path);
    }
    return choice;
  }

  /// Forgets the override, falling back to the environment and the platform
  /// default.
  static Future<void> clear() => PreferencesService.setAndroidSdkPath(null);

  /// Whether [path] can serve as an SDK root, and what to say about it.
  ///
  /// A directory with no emulator package is still accepted: it is the right
  /// SDK, just an incomplete one, and telling the user to install a package
  /// beats telling them they picked the wrong folder.
  @visibleForTesting
  static AndroidSdkChoice evaluate(String path) {
    if (!AndroidSdkPath.looksLikeSdk(path)) {
      return AndroidSdkChoice(
        path: path,
        accepted: false,
        message:
            'That folder does not look like an Android SDK. Pick the one that '
            'contains platform-tools and emulator — usually a folder named '
            'Sdk or sdk.',
      );
    }

    if (AndroidSdkPath.emulatorExecutable(path) == null) {
      return AndroidSdkChoice(
        path: path,
        accepted: true,
        message:
            'Using the SDK at $path, but it has no emulator package. Install '
            'it from Android Studio’s SDK Manager, under SDK Tools.',
      );
    }

    return AndroidSdkChoice(
      path: path,
      accepted: true,
      message: 'Using the Android SDK at $path.',
    );
  }
}
