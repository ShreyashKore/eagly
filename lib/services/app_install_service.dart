import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/device.dart';
import 'preferences_service.dart';

class AppInstallSelectionResult {
  const AppInstallSelectionResult({
    this.filePath,
    this.fileName,
    this.error,
    this.cancelled = false,
  });

  final String? filePath;
  final String? fileName;
  final String? error;
  final bool cancelled;

  bool get isSuccess => !cancelled && error == null && filePath != null;

  factory AppInstallSelectionResult.success({
    required String filePath,
    required String fileName,
  }) {
    return AppInstallSelectionResult(filePath: filePath, fileName: fileName);
  }

  factory AppInstallSelectionResult.failure({
    String? fileName,
    required String error,
  }) {
    return AppInstallSelectionResult(fileName: fileName, error: error);
  }

  factory AppInstallSelectionResult.cancelled() {
    return const AppInstallSelectionResult(cancelled: true);
  }
}

class AppInstallResult {
  const AppInstallResult({
    this.fileName,
    this.device,
    this.message,
    this.error,
    this.cancelled = false,
  });

  final String? fileName;
  final Device? device;
  final String? message;
  final String? error;
  final bool cancelled;

  bool get isSuccess => !cancelled && error == null;

  factory AppInstallResult.success({
    required String fileName,
    required Device device,
    required String message,
  }) {
    return AppInstallResult(
      fileName: fileName,
      device: device,
      message: message,
    );
  }

  factory AppInstallResult.failure({
    String? fileName,
    Device? device,
    required String error,
  }) {
    return AppInstallResult(fileName: fileName, device: device, error: error);
  }

  factory AppInstallResult.cancelled() {
    return const AppInstallResult(cancelled: true);
  }
}

class AppInstallService {
  static const List<String> _androidExtensions = ['apk'];
  static const List<String> _iosExtensions = ['ipa', 'app'];

  static Future<AppInstallSelectionResult> pickInstallable(Device device) async {
    final initialDirectory = await _resolveInitialDirectory();
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Install app on ${device.displayName}',
      initialDirectory: initialDirectory,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: supportedExtensionsFor(device),
    );

    if (result == null || result.files.isEmpty) {
      return AppInstallSelectionResult.cancelled();
    }

    final pickedFile = result.files.first;
    final filePath = pickedFile.path;
    final fileName = pickedFile.name.isNotEmpty
        ? pickedFile.name
        : (filePath == null ? 'Selected app' : extractFileName(filePath));
    if (filePath == null || filePath.trim().isEmpty) {
      return AppInstallSelectionResult.failure(
        fileName: fileName,
        error:
            'Failed to access "$fileName". Pick a local ${supportedFormatLabelFor(device)} file.',
      );
    }

    final validationError = validateInstallableForDevice(device, filePath);
    if (validationError != null) {
      return AppInstallSelectionResult.failure(
        fileName: fileName,
        error: validationError,
      );
    }

    return AppInstallSelectionResult.success(
      filePath: filePath,
      fileName: fileName,
    );
  }

  static List<String> supportedExtensionsFor(Device device) {
    return switch (device) {
      AndroidDevice() => List.unmodifiable(_androidExtensions),
      IosDevice() => List.unmodifiable(_iosExtensions),
    };
  }

  static String supportedFormatLabelFor(Device device) {
    return switch (device) {
      AndroidDevice() => 'APK',
      IosDevice() => 'IPA or .app bundle',
    };
  }

  static DevicePlatform? inferSupportedPlatform(String path) {
    final lowerPath = path.trim().toLowerCase();
    if (lowerPath.endsWith('.apk')) {
      return DevicePlatform.android;
    }
    if (lowerPath.endsWith('.ipa') || lowerPath.endsWith('.app')) {
      return DevicePlatform.ios;
    }
    return null;
  }

  static bool supportsInstallableForDevice(Device device, String path) {
    return validateInstallableForDevice(device, path) == null;
  }

  static String? validateInstallableForDevice(Device device, String path) {
    final normalizedPath = path.trim();
    final fileName = extractFileName(normalizedPath);
    if (normalizedPath.isEmpty) {
      return 'Select an app binary to install.';
    }

    final inferredPlatform = inferSupportedPlatform(normalizedPath);
    if (inferredPlatform == null) {
      return 'Unsupported app format for "$fileName". Supported formats are APK for Android and IPA / .app for iOS.';
    }

    if (inferredPlatform != device.platform) {
      final expectedFormat = supportedFormatLabelFor(device);
      return '"$fileName" is not supported for ${device.displayName}. Choose a $expectedFormat installable for the selected device.';
    }

    final entityType = FileSystemEntity.typeSync(normalizedPath, followLinks: true);
    if (entityType == FileSystemEntityType.notFound) {
      return 'The selected app "$fileName" could not be found.';
    }

    if (device is AndroidDevice) {
      if (!normalizedPath.toLowerCase().endsWith('.apk') ||
          entityType != FileSystemEntityType.file) {
        return 'Android installs require a local APK file.';
      }
      return null;
    }

    final lowerPath = normalizedPath.toLowerCase();
    if (lowerPath.endsWith('.ipa')) {
      return entityType == FileSystemEntityType.file
          ? null
          : 'iOS IPA installs require a local .ipa file.';
    }
    if (lowerPath.endsWith('.app')) {
      return entityType == FileSystemEntityType.directory
          ? null
          : 'iOS .app installs require a local .app bundle directory.';
    }

    return 'Unsupported iOS app format for "$fileName". Use an IPA or .app bundle.';
  }

  static String extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  static Future<void> rememberDialogDirectoryFromPath(String path) async {
    final entityType = FileSystemEntity.typeSync(path, followLinks: true);
    final directoryPath = switch (entityType) {
      FileSystemEntityType.directory => Directory(path).parent.path,
      FileSystemEntityType.file || FileSystemEntityType.link =>
        File(path).parent.path,
      FileSystemEntityType.notFound => File(path).parent.path,
      _ => File(path).parent.path,
    };

    if (!_isUsableInitialDirectory(directoryPath)) {
      return;
    }

    await PreferencesService.setLastFileDialogDirectory(directoryPath);
  }

  static Future<String?> _resolveInitialDirectory() async {
    final rememberedDirectory = PreferencesService.lastFileDialogDirectory;
    if (_isUsableInitialDirectory(rememberedDirectory)) {
      return rememberedDirectory;
    }

    for (final candidate in _defaultInitialDirectoryCandidates()) {
      if (_isUsableInitialDirectory(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  static Iterable<String> _defaultInitialDirectoryCandidates() sync* {
    final homeDirectory = _userHomeDirectory;
    if (homeDirectory == null || homeDirectory.isEmpty) {
      return;
    }

    yield '$homeDirectory${Platform.pathSeparator}Downloads';
    yield '$homeDirectory${Platform.pathSeparator}Documents';
    yield homeDirectory;
  }

  static bool _isUsableInitialDirectory(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }

    final directory = Directory(path);
    return directory.isAbsolute && directory.existsSync();
  }

  static String? get _userHomeDirectory {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return home;
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }

    final homeDrive = Platform.environment['HOMEDRIVE'];
    final homePath = Platform.environment['HOMEPATH'];
    if (homeDrive != null &&
        homeDrive.isNotEmpty &&
        homePath != null &&
        homePath.isNotEmpty) {
      return '$homeDrive$homePath';
    }

    return null;
  }
}

