import 'dart:typed_data';

import 'package:eagly/services/app_icon_cache.dart';

/// In-memory [AppIconCache] so icon tests never touch the real filesystem.
class FakeAppIconCache implements AppIconCache {
  final Map<String, Uint8List?> memory = {};
  final List<String> storedPackages = [];

  /// Every package [load] was asked for, in order — i.e. the disk reads the
  /// real cache would have made on a miss.
  final List<String> loadedPackages = [];

  void seed(String packageName, Uint8List bytes) => memory[packageName] = bytes;

  @override
  Future<Uint8List?> load(String packageName) async {
    loadedPackages.add(packageName);
    if (memory.containsKey(packageName)) return memory[packageName];
    memory[packageName] = null;
    return null;
  }

  @override
  Uint8List? peek(String packageName) => memory[packageName];

  @override
  Future<void> store(String packageName, Uint8List bytes) async {
    memory[packageName] = bytes;
    storedPackages.add(packageName);
  }

  final Map<String, String> labels = {};

  @override
  Map<String, String>? get cachedLabels => labels;

  @override
  Future<Map<String, String>> loadLabels() async => labels;

  @override
  Future<void> storeLabel(String packageName, String label) async {
    labels[packageName] = label;
  }
}
