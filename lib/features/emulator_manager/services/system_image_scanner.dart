import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/system_image.dart';

/// Finds the system images installed in an SDK by reading its
/// `system-images/` tree.
///
/// `sdkmanager --list_installed` reports the same thing, but costs a JVM start
/// and can reach for the network. The tree is laid out as
/// `system-images/<api>/<tag>/<abi>/source.properties`, and that file carries
/// everything needed — so this is a directory walk and a few small reads.
class SystemImageScanner {
  const SystemImageScanner();

  /// Every installed image, newest API first.
  ///
  /// Never throws: an unreadable SDK yields an empty list, which the create
  /// sheet renders as "no images installed" rather than an error.
  Future<List<SystemImage>> scan(String sdkRoot) async {
    final root = Directory(_join(sdkRoot, ['system-images']));
    if (!root.existsSync()) return const [];

    final images = <SystemImage>[];
    try {
      for (final apiDir in _subdirectories(root)) {
        for (final tagDir in _subdirectories(apiDir)) {
          for (final abiDir in _subdirectories(tagDir)) {
            final image = await _read(
              abiDir,
              apiSegment: _basename(apiDir.path),
              tagSegment: _basename(tagDir.path),
              abiSegment: _basename(abiDir.path),
            );
            if (image != null) images.add(image);
          }
        }
      }
    } on FileSystemException {
      return images;
    }

    images.sort(compareImages);
    return images;
  }

  /// Newest API first, then by tag and ABI so the order is stable between
  /// runs — a list that reshuffles itself is worse than one in any fixed order.
  @visibleForTesting
  static int compareImages(SystemImage left, SystemImage right) {
    final api = _compareApiLevels(right.apiLevel, left.apiLevel);
    if (api != 0) return api;
    final tag = left.tagDisplay.compareTo(right.tagDisplay);
    if (tag != 0) return tag;
    return left.abi.compareTo(right.abi);
  }

  /// Compares `36.1` against `36` numerically, segment by segment — a string
  /// compare puts `android-9` above `android-35`.
  static int _compareApiLevels(String left, String right) {
    final leftParts = left.split('.');
    final rightParts = right.split('.');
    for (var i = 0; i < leftParts.length || i < rightParts.length; i++) {
      final l = i < leftParts.length ? int.tryParse(leftParts[i]) ?? 0 : 0;
      final r = i < rightParts.length ? int.tryParse(rightParts[i]) ?? 0 : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  Future<SystemImage?> _read(
    Directory abiDir, {
    required String apiSegment,
    required String tagSegment,
    required String abiSegment,
  }) async {
    final properties = await _readProperties(
      File(_join(abiDir.path, ['source.properties'])),
    );
    // No source.properties means no installed package here — a leftover or a
    // partial download, and launching against it would fail.
    if (properties.isEmpty) return null;

    return buildImage(
      properties: properties,
      apiSegment: apiSegment,
      tagSegment: tagSegment,
      abiSegment: abiSegment,
    );
  }

  /// Builds the model from an already-parsed `source.properties`.
  ///
  /// The directory names are the fallback for every field, because the package
  /// path is assembled from them: an image whose properties disagree with its
  /// own location would otherwise get a path `avdmanager` cannot resolve.
  @visibleForTesting
  static SystemImage buildImage({
    required Map<String, String> properties,
    required String apiSegment,
    required String tagSegment,
    required String abiSegment,
  }) {
    final tagId = properties['SystemImage.TagId'] ?? tagSegment;
    return SystemImage(
      packagePath: 'system-images;$apiSegment;$tagSegment;$abiSegment',
      apiLevel:
          properties['AndroidVersion.ApiLevel'] ??
          apiSegment.replaceFirst('android-', ''),
      tagId: tagId,
      tagDisplay: properties['SystemImage.TagDisplay'] ?? tagId,
      abi: properties['SystemImage.Abi'] ?? abiSegment,
      vendorDisplay: properties['Addon.VendorDisplay'],
    );
  }

  @visibleForTesting
  static Map<String, String> parseProperties(String contents) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(contents)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      values[trimmed.substring(0, separator).trim()] = trimmed
          .substring(separator + 1)
          .trim();
    }
    return values;
  }

  Future<Map<String, String>> _readProperties(File file) async {
    try {
      if (!file.existsSync()) return const {};
      return parseProperties(await file.readAsString());
    } catch (_) {
      return const {};
    }
  }

  List<Directory> _subdirectories(Directory directory) {
    try {
      return directory.listSync().whereType<Directory>().toList()
        ..sort((left, right) => left.path.compareTo(right.path));
    } catch (_) {
      return const [];
    }
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;

  static String _join(String parent, List<String> segments) =>
      [parent, ...segments].join(Platform.pathSeparator);
}
