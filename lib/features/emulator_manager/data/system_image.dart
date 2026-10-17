import 'package:flutter/foundation.dart';

/// A system image already installed in the SDK.
///
/// Only installed ones exist here. Downloading an image is a different feature
/// entirely — `sdkmanager`, licence acceptance and a multi-gigabyte transfer —
/// while creating an AVD from one already on disk is a single command.
@immutable
class const SystemImage({
  required this.packagePath,
  required this.apiLevel,
  required this.tagId,
  required this.tagDisplay,
  required this.abi,
  this.vendorDisplay,
}) {
  /// What `avdmanager create avd -k` takes, e.g.
  /// `system-images;android-34;google_apis_playstore;arm64-v8a`.
  final String packagePath;

  /// A string, not an int: minor-versioned platforms (`36.1`) are real.
  final String apiLevel;

  /// `google_apis_playstore`, `android-tv`, …
  final String tagId;

  /// The same tag as shown to humans, e.g. `Google Play`.
  final String tagDisplay;

  final String abi;
  final String? vendorDisplay;

  bool get hasPlayStore => tagId.contains('playstore');

  /// Tags that name a device class rather than an API flavour.
  ///
  /// Anything not listed is treated as a phone/tablet image, which is both the
  /// common case and the safe default: an unrecognised tag pairs with the
  /// untagged device profiles, which is where a new tag would land anyway.
  static const _deviceClassTags = {
    'android-automotive',
    'android-automotive-playstore',
    'android-automotive-distantdisplay',
    'android-desktop',
    'android-tv',
    'android-wear',
    'android-xr',
    'ai-glasses',
    'google-tv',
  };

  bool get isHandheld => !_deviceClassTags.contains(tagId);

  /// `API 34 · Google Play · arm64-v8a`
  String get label => 'API $apiLevel · $tagDisplay · $abi';

  @override
  bool operator ==(Object other) =>
      other is SystemImage &&
      other.packagePath == packagePath &&
      other.apiLevel == apiLevel &&
      other.tagId == tagId &&
      other.tagDisplay == tagDisplay &&
      other.abi == abi &&
      other.vendorDisplay == vendorDisplay;

  @override
  int get hashCode =>
      Object.hash(packagePath, apiLevel, tagId, tagDisplay, abi, vendorDisplay);

  @override
  String toString() => 'SystemImage($packagePath)';
}
