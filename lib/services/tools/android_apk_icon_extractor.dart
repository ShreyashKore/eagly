import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';

/// Best-effort launcher icon extraction from an Android APK, entirely in
/// Dart — Eagly bundles bare `adb`, not `aapt`/`aapt2`, so there is no
/// off-the-shelf tool to ask for a decoded icon. This parses the binary
/// AndroidManifest.xml ("AXML") to find the `android:icon` resource
/// reference on `<application>`, then resolves it through resources.arsc
/// ("ARSC") to a raster file entry inside the APK's zip — PNG or WebP,
/// whatever the app shipped; both decode fine via `Image.memory`.
///
/// Deliberately best-effort: modern "adaptive icons" split background/
/// foreground layers, so one level of `<foreground>` resolution is attempted
/// when only an adaptive-icon XML is found (or when the only plain raster
/// fallback is a suspiciously tiny — likely blank — legacy placeholder);
/// some apps ship the foreground layer itself as a vector-drawable XML with
/// no raster fallback, which can't be rendered here. Any parsing surprise
/// (malformed/unexpected chunk layout — real APKs vary a lot) is swallowed
/// by returning null rather than throwing, so a bad icon never takes down
/// the app list.
class ApkIconExtractor {
  const ApkIconExtractor._();

  static const int _androidAttrIcon = 0x01010002;
  static const int _androidAttrRoundIcon = 0x0101021c;
  static const int _androidAttrDrawable = 0x01010119;

  static const int _typeReference = 0x01;

  /// Below this size a "raster" icon is more likely a near-blank legacy
  /// placeholder (kept only for pre-API-26 compatibility) than real artwork,
  /// so the adaptive-icon layers are tried first when one is available.
  static const int _minPlausibleIconBytes = 300;

  /// Returns the launcher icon's raw image bytes, or null when it can't be
  /// resolved (missing entries, unsupported vector-only icon, parse error).
  static Uint8List? extractIconBytes(Uint8List apkBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(apkBytes, verify: false);
      final manifestBytes = _readEntry(archive, 'AndroidManifest.xml');
      final arscBytes = _readEntry(archive, 'resources.arsc');
      if (manifestBytes == null || arscBytes == null) return null;

      final iconResId = _findApplicationIconResourceId(manifestBytes);
      if (iconResId == null) return null;

      final table = _ResourceTable.parse(arscBytes);
      if (table == null) return null;

      return _resolveBestIconBytes(table, iconResId, archive);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _resolveBestIconBytes(
    _ResourceTable table,
    int resourceId,
    Archive archive, {
    bool allowRecurse = true,
  }) {
    final candidates = table.resolveFileCandidates(resourceId);
    if (candidates.isEmpty) return null;

    final raster =
        candidates.where((c) => !c.path.toLowerCase().endsWith('.xml')).toList()
          ..sort((a, b) => b.density.compareTo(a.density));

    Uint8List? bestRaster;
    for (final candidate in raster) {
      final bytes = _readEntry(archive, candidate.path);
      if (bytes == null) continue;
      bestRaster ??= bytes;
      if (bytes.length >= _minPlausibleIconBytes) return bytes;
    }

    // Only tiny/blank raster (or none at all) so far — try resolving one
    // level into the adaptive icon's <foreground> (falling back to
    // <background>) layer, which is often more representative artwork.
    if (allowRecurse) {
      final xmlCandidates = candidates.where(
        (c) => c.path.toLowerCase().endsWith('.xml'),
      );
      for (final candidate in xmlCandidates) {
        final xmlBytes = _readEntry(archive, candidate.path);
        if (xmlBytes == null) continue;
        final layerResId = _findAdaptiveIconLayerResourceId(xmlBytes);
        if (layerResId == null) continue;
        final resolved = _resolveBestIconBytes(
          table,
          layerResId,
          archive,
          allowRecurse: false,
        );
        if (resolved != null) return resolved;
      }
    }

    return bestRaster;
  }

  static Uint8List? _readEntry(Archive archive, String name) {
    final file = archive.files.firstWhereOrNull(
      (f) => f.isFile && (f.name == name || f.name.endsWith('/$name')),
    );
    return file?.content;
  }

  static int? _findApplicationIconResourceId(Uint8List manifestBytes) {
    for (final element in _AxmlParser.parseElements(manifestBytes)) {
      if (element.name != 'application') continue;
      final icon = element.attributesByResId[_androidAttrIcon];
      if (icon != null && icon.dataType == _typeReference) return icon.data;
      final roundIcon = element.attributesByResId[_androidAttrRoundIcon];
      if (roundIcon != null && roundIcon.dataType == _typeReference) {
        return roundIcon.data;
      }
    }
    return null;
  }

  static int? _findAdaptiveIconLayerResourceId(Uint8List xmlBytes) {
    final elements = _AxmlParser.parseElements(xmlBytes);
    for (final tagName in const ['foreground', 'background']) {
      for (final element in elements) {
        if (element.name != tagName) continue;
        final drawable = element.attributesByResId[_androidAttrDrawable];
        if (drawable != null && drawable.dataType == _typeReference) {
          return drawable.data;
        }
      }
    }
    return null;
  }
}

// ── Binary XML (AXML) — just enough to read start-element attributes ───────

class _TypedValue {
  const _TypedValue(this.dataType, this.data);
  final int dataType;
  final int data;
}

class _AxmlElement {
  const _AxmlElement(this.name, this.attributesByResId);
  final String name;
  final Map<int, _TypedValue> attributesByResId;
}

/// Minimal AXML walker: yields every start-element tag with its attributes
/// keyed by *resource id* (resolved via the resource map chunk), which is
/// how `android:xxx` attributes are addressed in compiled XML. Namespaces,
/// nesting, and text nodes are irrelevant to icon resolution and are
/// skipped.
class _AxmlParser {
  static const int _typeXml = 0x0003;
  static const int _typeStringPool = 0x0001;
  static const int _typeResourceMap = 0x0180;
  static const int _typeStartElement = 0x0102;

  static List<_AxmlElement> parseElements(Uint8List bytes) {
    final elements = <_AxmlElement>[];
    if (bytes.length < 8) return elements;
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(0, Endian.little) != _typeXml) return elements;

    _StringPool? stringPool;
    List<int>? resourceMap;
    var offset = 8;

    while (offset + 8 <= bytes.length) {
      final chunkType = data.getUint16(offset, Endian.little);
      final headerSize = data.getUint16(offset + 2, Endian.little);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkSize < 8 || offset + chunkSize > bytes.length) break;

      switch (chunkType) {
        case _typeStringPool:
          stringPool = _StringPool.parse(bytes, offset);
        case _typeResourceMap:
          final count = (chunkSize - headerSize) ~/ 4;
          resourceMap = List<int>.generate(
            count,
            (i) => data.getUint32(offset + headerSize + i * 4, Endian.little),
          );
        case _typeStartElement:
          final element = _parseStartElement(
            data,
            bytes,
            offset,
            stringPool,
            resourceMap,
          );
          if (element != null) elements.add(element);
      }

      offset += chunkSize;
    }
    return elements;
  }

  static _AxmlElement? _parseStartElement(
    ByteData data,
    Uint8List bytes,
    int chunkStart,
    _StringPool? pool,
    List<int>? resourceMap,
  ) {
    if (pool == null) return null;
    // Node header (16 bytes: chunk header + lineNumber + comment), then the
    // ResXMLTree_attrExt body.
    final extStart = chunkStart + 16;
    if (extStart + 20 > bytes.length) return null;

    final nameIdx = data.getUint32(extStart + 4, Endian.little);
    final attrStart = data.getUint16(extStart + 8, Endian.little);
    final attrSize = data.getUint16(extStart + 10, Endian.little);
    final attrCount = data.getUint16(extStart + 12, Endian.little);

    final name = pool.stringAt(nameIdx);
    if (name == null) return null;

    final attrsByResId = <int, _TypedValue>{};
    final attrsBase = extStart + attrStart;
    for (var i = 0; i < attrCount; i++) {
      final attrOffset = attrsBase + i * attrSize;
      if (attrOffset + 20 > bytes.length) break;
      final attrNameIdx = data.getUint32(attrOffset + 4, Endian.little);
      final dataType = data.getUint8(attrOffset + 15);
      final value = data.getUint32(attrOffset + 16, Endian.little);
      if (resourceMap != null && attrNameIdx < resourceMap.length) {
        attrsByResId[resourceMap[attrNameIdx]] = _TypedValue(dataType, value);
      }
    }

    return _AxmlElement(name, attrsByResId);
  }
}

/// Shared string pool decoder (used for both AXML and the ARSC's global
/// pool) — UTF-8 or UTF-16LE, chosen per the pool's flags.
class _StringPool {
  _StringPool(this._bytes, this._offsets, this._stringsStart, this._isUtf8);

  final Uint8List _bytes;
  final List<int> _offsets;
  final int _stringsStart;
  final bool _isUtf8;
  final Map<int, String> _cache = {};

  static _StringPool? parse(Uint8List bytes, int chunkStart) {
    final data = ByteData.sublistView(bytes);
    if (chunkStart + 28 > bytes.length) return null;
    final stringCount = data.getUint32(chunkStart + 8, Endian.little);
    final flags = data.getUint32(chunkStart + 16, Endian.little);
    final stringsStartRel = data.getUint32(chunkStart + 20, Endian.little);
    final isUtf8 = (flags & 0x100) != 0;

    final offsets = <int>[];
    for (var i = 0; i < stringCount; i++) {
      final pos = chunkStart + 28 + i * 4;
      if (pos + 4 > bytes.length) break;
      offsets.add(data.getUint32(pos, Endian.little));
    }
    return _StringPool(bytes, offsets, chunkStart + stringsStartRel, isUtf8);
  }

  String? stringAt(int index) {
    if (index < 0 || index >= _offsets.length) return null;
    final cached = _cache[index];
    if (cached != null) return cached;
    try {
      final decoded = _decodeAt(_stringsStart + _offsets[index]);
      _cache[index] = decoded;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  String _decodeAt(int start) {
    if (_isUtf8) {
      var pos = start;
      final charLen = _decode7or15(pos);
      pos += charLen.consumed;
      final byteLen = _decode7or15(pos);
      pos += byteLen.consumed;
      final strBytes = _bytes.sublist(pos, pos + byteLen.length);
      return utf8.decode(strBytes, allowMalformed: true);
    }

    var pos = start;
    final charLen = _decode16(pos);
    pos += charLen.consumed;
    final byteLen = charLen.length * 2;
    final units = <int>[];
    for (var i = 0; i < byteLen; i += 2) {
      units.add(_bytes[pos + i] | (_bytes[pos + i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  ({int length, int consumed}) _decode7or15(int pos) {
    final first = _bytes[pos];
    if ((first & 0x80) != 0) {
      final second = _bytes[pos + 1];
      return (length: ((first & 0x7F) << 8) | second, consumed: 2);
    }
    return (length: first, consumed: 1);
  }

  ({int length, int consumed}) _decode16(int pos) {
    final first = _bytes[pos] | (_bytes[pos + 1] << 8);
    if ((first & 0x8000) != 0) {
      final second = _bytes[pos + 2] | (_bytes[pos + 3] << 8);
      return (length: ((first & 0x7FFF) << 16) | second, consumed: 4);
    }
    return (length: first, consumed: 2);
  }
}

// ── Compiled resource table (ARSC) — resolves a resource id to candidate
// file paths across every density/config variant it has. ───────────────────

class _FileCandidate {
  const _FileCandidate(this.density, this.path);
  final int density;
  final String path;
}

class _ResourceTable {
  _ResourceTable(this._globalStrings, this._packages);
  final _StringPool _globalStrings;
  final List<_ArscPackage> _packages;

  static const int _typeStringPool = 0x0001;
  static const int _typePackage = 0x0200;

  static _ResourceTable? parse(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(0, Endian.little) != 0x0002) return null;

    final headerSize = data.getUint16(2, Endian.little);
    final totalSize = data.getUint32(4, Endian.little);
    final end = totalSize <= bytes.length ? totalSize : bytes.length;

    _StringPool? globalPool;
    final packages = <_ArscPackage>[];
    var offset = headerSize;

    while (offset + 8 <= end) {
      final chunkType = data.getUint16(offset, Endian.little);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkSize < 8 || offset + chunkSize > bytes.length) break;

      if (chunkType == _typeStringPool) {
        globalPool ??= _StringPool.parse(bytes, offset);
      } else if (chunkType == _typePackage) {
        final pkg = _ArscPackage.parse(bytes, offset, chunkSize);
        if (pkg != null) packages.add(pkg);
      }
      offset += chunkSize;
    }

    if (globalPool == null || packages.isEmpty) return null;
    return _ResourceTable(globalPool, packages);
  }

  List<_FileCandidate> resolveFileCandidates(int resourceId) {
    final packageId = (resourceId >> 24) & 0xFF;
    final typeId = (resourceId >> 16) & 0xFF;
    final entryId = resourceId & 0xFFFF;

    final pkg = _packages.firstWhereOrNull((p) => p.id == packageId);
    if (pkg == null) return const [];

    final candidates = <_FileCandidate>[];
    for (final type in pkg.types) {
      if (type.id != typeId) continue;
      final value = type.resolveEntryValue(entryId);
      if (value == null || value.dataType != 0x03) continue;
      final path = _globalStrings.stringAt(value.data);
      if (path == null) continue;
      candidates.add(_FileCandidate(type.density, path));
    }
    return candidates;
  }
}

class _ArscPackage {
  _ArscPackage(this.id, this.types);
  final int id;
  final List<_ArscType> types;

  static const int _typeType = 0x0201;

  static _ArscPackage? parse(Uint8List bytes, int chunkStart, int chunkSize) {
    if (chunkStart + 12 > bytes.length) return null;
    final data = ByteData.sublistView(bytes);
    final id = data.getUint32(chunkStart + 8, Endian.little);
    final headerSize = data.getUint16(chunkStart + 2, Endian.little);
    final chunkEnd = chunkStart + chunkSize;

    final types = <_ArscType>[];
    var offset = chunkStart + headerSize;
    while (offset + 8 <= chunkEnd && offset + 8 <= bytes.length) {
      final subType = data.getUint16(offset, Endian.little);
      final subSize = data.getUint32(offset + 4, Endian.little);
      if (subSize < 8 || offset + subSize > bytes.length) break;

      if (subType == _typeType) {
        final type = _ArscType.parse(bytes, offset);
        if (type != null) types.add(type);
      }
      offset += subSize;
    }

    return _ArscPackage(id, types);
  }
}

class _ArscType {
  final int id;
  final int density;
  final Uint8List _bytes;
  final int _entriesStart;
  final int _entryCount;
  final bool _sparse;
  final bool _offset16;

  static const int _noEntry32 = 0xFFFFFFFF;
  static const int _noEntry16 = 0xFFFF;
  static const int _flagComplex = 0x0001;

  static _ArscType? parse(Uint8List bytes, int chunkStart) {
    if (chunkStart + 20 > bytes.length) return null;
    final data = ByteData.sublistView(bytes);
    final id = data.getUint8(chunkStart + 8);
    final flags = data.getUint8(chunkStart + 9);
    final entryCount = data.getUint32(chunkStart + 12, Endian.little);
    final entriesStartRel = data.getUint32(chunkStart + 16, Endian.little);

    var density = 0;
    final configStart = chunkStart + 20;
    if (configStart + 4 <= bytes.length) {
      final configSize = data.getUint32(configStart, Endian.little);
      if (configSize >= 16 && configStart + 16 <= bytes.length) {
        density = data.getUint16(configStart + 14, Endian.little);
      }
    }

    return _ArscType(
      id,
      density,
      bytes,
      chunkStart + entriesStartRel,
      entryCount,
      (flags & 0x01) != 0, // FLAG_SPARSE
      (flags & 0x02) != 0, // FLAG_OFFSET16
    );
  }

  _ArscType(
    this.id,
    this.density,
    this._bytes,
    this._entriesStart,
    this._entryCount,
    this._sparse,
    this._offset16,
  );

  _TypedValue? resolveEntryValue(int entryId) {
    final data = ByteData.sublistView(_bytes);
    int? entryOffset;

    if (_sparse) {
      // ResTable_sparseTypeEntry: uint16 idx, uint16 offset (offset*4 = real).
      for (var i = 0; i < _entryCount; i++) {
        final pos = _entriesStart + i * 4;
        if (pos + 4 > _bytes.length) break;
        final idx = data.getUint16(pos, Endian.little);
        if (idx == entryId) {
          entryOffset = data.getUint16(pos + 2, Endian.little) * 4;
          break;
        }
      }
    } else if (_offset16) {
      if (entryId < 0 || entryId >= _entryCount) return null;
      final pos = _entriesStart + entryId * 2;
      if (pos + 2 > _bytes.length) return null;
      final off16 = data.getUint16(pos, Endian.little);
      if (off16 == _noEntry16) return null;
      entryOffset = off16 * 4;
    } else {
      if (entryId < 0 || entryId >= _entryCount) return null;
      final pos = _entriesStart + entryId * 4;
      if (pos + 4 > _bytes.length) return null;
      final off = data.getUint32(pos, Endian.little);
      if (off == _noEntry32) return null;
      entryOffset = off;
    }

    if (entryOffset == null) return null;
    final absEntry = _entriesStart + entryOffset;
    if (absEntry + 8 > _bytes.length) return null;

    // ResTable_entry is a union of `Full {size; flags; key}` and
    // `Compact {key; flags; data}` — `flags` sits at the same offset (2) in
    // both, so it's always safe to read first and branch on FLAG_COMPLEX.
    //
    // The AOSP header documents a per-entry FLAG_COMPACT (0x0008) bit to pick
    // between the two, but real APKs built by modern aapt2 emit the compact
    // layout for every simple entry *without ever setting that bit* — the
    // low byte of `flags` is 0 and the high byte is the Res_value dataType,
    // verified against `aapt dump --values resources` on a real APK. So try
    // compact first (the modern default); only a null/implausible dataType
    // falls back to the legacy trailing-Res_value layout for older tooling.
    final entryFlags = data.getUint16(absEntry + 2, Endian.little);
    if ((entryFlags & _flagComplex) != 0) return null; // complex (map) entry

    final compactDataType = (entryFlags >> 8) & 0xFF;
    if (compactDataType != 0) {
      final valueData = data.getUint32(absEntry + 4, Endian.little);
      return _TypedValue(compactDataType, valueData);
    }

    final entrySize = data.getUint16(absEntry, Endian.little);
    final valueOffset = absEntry + entrySize;
    if (entrySize < 8 || valueOffset + 8 > _bytes.length) return null;
    final dataType = data.getUint8(valueOffset + 3);
    final valueData = data.getUint32(valueOffset + 4, Endian.little);
    return _TypedValue(dataType, valueData);
  }
}
