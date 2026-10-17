import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Google Play's list of supported devices: retail branding, marketing name,
/// device codename (`ro.product.device`) and model (`ro.product.model`).
/// Served as UTF-16 with a byte-order mark.
const _supportedDevicesUrl =
    'https://storage.googleapis.com/play_public/supported_devices.csv';

const _cacheFileName = 'android_supported_devices.csv';

/// A cached copy older than this is refreshed in the background — new devices
/// land on the list every week, and a stale copy is still better than none.
const _cacheMaxAge = Duration(days: 30);

const _downloadTimeout = Duration(seconds: 30);

/// Marketing names for Android devices ("Galaxy S23" for `SM-S911B`), built
/// from Google Play's supported-devices list.
class AndroidDeviceCatalog {
  AndroidDeviceCatalog._(this._byDeviceAndModel, this._byModel, this._byDevice);

  /// Parses the supported-devices CSV, decoded to a string. Rows without a
  /// marketing name are dropped — they have nothing to offer.
  factory AndroidDeviceCatalog.parse(String csv) {
    final byDeviceAndModel = <String, List<_CatalogEntry>>{};
    final byModel = <String, List<_CatalogEntry>>{};
    final byDevice = <String, List<_CatalogEntry>>{};
    var header = true;
    for (final line in const LineSplitter().convert(csv)) {
      if (header) {
        header = false;
        continue;
      }
      final fields = _parseCsvLine(line);
      if (fields.length < 4) continue;
      final marketingName = fields[1].trim();
      if (marketingName.isEmpty) continue;
      final entry = _CatalogEntry(
        branding: fields[0].trim().toLowerCase(),
        marketingName: marketingName,
      );
      final device = _key(fields[2]);
      final model = _key(fields[3]);
      if (device != null && model != null) {
        (byDeviceAndModel['$device\n$model'] ??= []).add(entry);
      }
      if (model != null) (byModel[model] ??= []).add(entry);
      if (device != null) (byDevice[device] ??= []).add(entry);
    }
    return AndroidDeviceCatalog._(byDeviceAndModel, byModel, byDevice);
  }

  final Map<String, List<_CatalogEntry>> _byDeviceAndModel;
  final Map<String, List<_CatalogEntry>> _byModel;
  final Map<String, List<_CatalogEntry>> _byDevice;

  bool get isEmpty => _byModel.isEmpty && _byDevice.isEmpty;

  /// The marketing name for a device's [brand] (`ro.product.brand`), [device]
  /// codename and [model], or null when the list has no unambiguous answer.
  ///
  /// The codename + model pair is the list's own key, so it wins. A model alone
  /// is usually distinctive too. A codename alone is not (`komodo` is both a
  /// Pixel and a SMART board), so it is only trusted for a matching brand.
  String? lookup({String? brand, String? device, String? model}) {
    final brandKey = _key(brand);
    final deviceKey = _key(device);
    final modelKey = _key(model);
    if (deviceKey != null && modelKey != null) {
      final rows = _byDeviceAndModel['$deviceKey\n$modelKey'];
      if (rows != null) {
        final branded = _withBrand(rows, brandKey);
        return (branded.isEmpty ? rows : branded).first.marketingName;
      }
    }
    if (modelKey != null) {
      final rows = _byModel[modelKey];
      if (rows != null) {
        final branded = _withBrand(rows, brandKey);
        final name = _unique(branded.isEmpty ? rows : branded);
        if (name != null) return name;
      }
    }
    if (deviceKey != null && brandKey != null) {
      final rows = _byDevice[deviceKey];
      if (rows != null) return _unique(_withBrand(rows, brandKey));
    }
    return null;
  }

  static List<_CatalogEntry> _withBrand(
    List<_CatalogEntry> rows,
    String? brandKey,
  ) {
    if (brandKey == null) return const [];
    return rows.where((row) => row.branding == brandKey).toList();
  }

  /// The one marketing name every row agrees on, or null.
  static String? _unique(List<_CatalogEntry> rows) {
    if (rows.isEmpty) return null;
    final name = rows.first.marketingName;
    return rows.every((row) => row.marketingName == name) ? name : null;
  }

  static String? _key(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Splits one CSV line: quoted fields with `""` escapes. The list also
  /// carries stray `\'` escapes (`Alba 7\'\'`), which are unescaped.
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(char);
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        fields.add(field.toString());
        field.clear();
      } else {
        field.write(char);
      }
    }
    fields.add(field.toString());
    return [for (final value in fields) value.replaceAll(r"\'", "'")];
  }

  /// Decodes the downloaded bytes: UTF-16 (either byte order) when they start
  /// with a byte-order mark, UTF-8 otherwise.
  @visibleForTesting
  static String decode(List<int> bytes) {
    if (bytes.length >= 2) {
      final littleEndian = bytes[0] == 0xFF && bytes[1] == 0xFE;
      final bigEndian = bytes[0] == 0xFE && bytes[1] == 0xFF;
      if (littleEndian || bigEndian) {
        final units = List<int>.filled((bytes.length - 2) ~/ 2, 0);
        for (var i = 0; i < units.length; i++) {
          final a = bytes[2 + i * 2];
          final b = bytes[3 + i * 2];
          units[i] = littleEndian ? a | (b << 8) : (a << 8) | b;
        }
        return String.fromCharCodes(units);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _CatalogEntry {
  const _CatalogEntry({required this.branding, required this.marketingName});

  /// Lower-cased "Retail Branding", compared against `ro.product.brand`.
  final String branding;
  final String marketingName;
}

/// Loads [AndroidDeviceCatalog] and answers lookups against it.
///
/// The list (~5 MB) is downloaded once and cached under the app support
/// directory. A lookup never waits — not on the network, and not on reading
/// and parsing the cached copy either, which takes a noticeable moment: until
/// the list is in memory it answers null and starts loading it (from disk,
/// else by download), then notifies listeners once it is in so callers can
/// look again. A failed download is retried every
/// [retryDelay]. A cached copy past [_cacheMaxAge] keeps answering while a
/// fresh one downloads.
class AndroidMarketingNames extends ChangeNotifier {
  AndroidMarketingNames._(this._url, this._cacheDirectory);

  /// Loads from [url] and caches in [cacheDirectory] instead of Google Play
  /// and the app support directory.
  @visibleForTesting
  AndroidMarketingNames.forTesting({
    required Uri url,
    required Directory cacheDirectory,
  }) : this._(url, () async => cacheDirectory);

  static final AndroidMarketingNames instance = AndroidMarketingNames._(
    Uri.parse(_supportedDevicesUrl),
    getApplicationSupportDirectory,
  );

  /// How long after a failed download the next attempt starts. Retries run
  /// on their own rather than waiting for a lookup, so a device described
  /// while offline still gets its name once the network is back.
  @visibleForTesting
  static Duration retryDelay = const Duration(minutes: 10);

  final Uri _url;
  final Future<Directory> Function() _cacheDirectory;

  AndroidDeviceCatalog? _catalog;
  Future<void>? _diskLoad;
  bool _disposed = false;
  Future<void>? _download;
  Timer? _retryTimer;

  /// The marketing name Google Play lists for a device, or null when it is
  /// not listed or the list isn't in memory yet — in which case loading it
  /// starts, and listeners hear when it lands.
  Future<String?> lookup({String? brand, String? device, String? model}) async {
    final catalog = _catalog;
    if (catalog == null) {
      _diskLoad ??= _loadFromDisk();
      return null;
    }
    return catalog.lookup(brand: brand, device: device, model: model);
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final catalog = await _parseFileInIsolate(file.path);
        if (!catalog.isEmpty) {
          _catalog = catalog;
          _notify();
          final age = DateTime.now().difference(await file.lastModified());
          if (age > _cacheMaxAge) _startDownload(file);
          return;
        }
      }
      _startDownload(file);
    } catch (_) {
      // No support directory or an unreadable cache: lookups answer null.
    }
  }

  void _startDownload(File cacheFile) {
    if (_download != null || (_retryTimer?.isActive ?? false)) return;
    _download = _downloadTo(cacheFile).whenComplete(() => _download = null);
  }

  Future<void> _downloadTo(File cacheFile) async {
    final client = HttpClient()..connectionTimeout = _downloadTimeout;
    try {
      final request = await client.getUrl(_url);
      final response = await request.close().timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        throw HttpException('Supported devices list: ${response.statusCode}');
      }
      final data = await response
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d))
          .timeout(_downloadTimeout)
          .then((builder) => builder.takeBytes());
      final catalog = await _parseInIsolate(data);
      if (catalog.isEmpty) throw const FormatException('Empty device list');
      _catalog = catalog;
      await _writeCache(cacheFile, data);
      _notify();
    } catch (_) {
      _retryTimer = Timer(retryDelay, () => _startDownload(cacheFile));
    } finally {
      client.close(force: true);
    }
  }

  // Static so the isolate closures capture only their argument: one built in
  // an instance method would also capture `this`, whose timer and listeners
  // can't be sent to another isolate.
  static Future<AndroidDeviceCatalog> _parseFileInIsolate(String path) =>
      Isolate.run(
        () => AndroidDeviceCatalog.parse(
          AndroidDeviceCatalog.decode(File(path).readAsBytesSync()),
        ),
      );

  static Future<AndroidDeviceCatalog> _parseInIsolate(List<int> data) =>
      Isolate.run(
        () => AndroidDeviceCatalog.parse(AndroidDeviceCatalog.decode(data)),
      );

  /// Writes [data] beside [cacheFile] and renames it into place, so a crash
  /// mid-write leaves the previous copy (or none) rather than a truncated one
  /// that would look fresh for [_cacheMaxAge].
  static Future<void> _writeCache(File cacheFile, List<int> data) async {
    final temp = File('${cacheFile.path}.download');
    try {
      await cacheFile.parent.create(recursive: true);
      await temp.writeAsBytes(data, flush: true);
      await temp.rename(cacheFile.path);
    } catch (_) {
      // Ignore cache write errors; the list is still in memory.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  Future<File> _cacheFile() async {
    final directory = await _cacheDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_cacheFileName');
  }

  /// Loads finish on their own schedule, possibly after [dispose].
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
