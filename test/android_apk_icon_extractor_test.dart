import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eagly/services/tools/android_apk_icon_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApkIconExtractor', () {
    test('returns null for empty bytes rather than throwing', () {
      expect(ApkIconExtractor.extractIconBytes(Uint8List(0)), isNull);
    });

    test('returns null for bytes that are not a zip archive', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(256, (i) => i % 256),
      );
      expect(ApkIconExtractor.extractIconBytes(garbage), isNull);
    });

    test('returns null for a well-formed but empty zip archive', () {
      // A minimal valid (empty) ZIP: just the End Of Central Directory record.
      final emptyZip = Uint8List.fromList([
        0x50, 0x4B, 0x05, 0x06, // EOCD signature
        0x00, 0x00, 0x00, 0x00, // disk numbers
        0x00, 0x00, 0x00, 0x00, // entry counts
        0x00, 0x00, 0x00, 0x00, // central directory size
        0x00, 0x00, 0x00, 0x00, // central directory offset
        0x00, 0x00, // comment length
      ]);
      expect(ApkIconExtractor.extractIconBytes(emptyZip), isNull);
    });

    test('reads no package name from a missing or non-zip file', () {
      final dir = Directory.systemTemp.createTempSync('apk_package');
      addTearDown(() => dir.deleteSync(recursive: true));
      final notApk = File('${dir.path}/a.apk')..writeAsStringSync('not a zip');

      expect(
        ApkIconExtractor.readPackageName('${dir.path}/missing.apk'),
        isNull,
      );
      expect(ApkIconExtractor.readPackageName(notApk.path), isNull);
    });

    test('a stored icon does not keep the whole APK in memory', () {
      final png = Uint8List.fromList(List<int>.generate(512, (i) => i % 251));
      final apk = _apkWithStoredIcon(png);

      final icon = ApkIconExtractor.extractDetails(apk).icon;

      expect(icon, png);
      // AppIconCache holds icons for the life of the process, so a view into
      // the APK here would pin every byte of it there.
      expect(icon!.buffer.lengthInBytes, icon.length);
    });
  });
}

/// The smallest APK the extractor resolves an icon from, with every entry
/// stored uncompressed the way real APKs store their PNGs. Padded so the APK
/// is clearly bigger than the icon.
Uint8List _apkWithStoredIcon(Uint8List icon) {
  ArchiveFile stored(String name, Uint8List bytes) =>
      ArchiveFile.bytes(name, bytes)..compression = CompressionType.none;

  return ZipEncoder().encodeBytes(
    Archive()
      ..add(stored('AndroidManifest.xml', _manifest()))
      ..add(stored('resources.arsc', _resourceTable()))
      ..add(stored('res/icon.png', icon))
      ..add(stored('classes.dex', Uint8List(64 * 1024))),
  );
}

const _iconResourceId = 0x7f010000;

/// Binary AXML for `<application android:icon="@0x7f010000"/>`.
Uint8List _manifest() {
  const androidAttrIcon = 0x01010002;
  const typeReference = 0x01;
  const none = 0xFFFFFFFF;

  final body = BytesBuilder()
    ..add(_stringPool(['icon', 'application']))
    ..add(_chunk(0x0180, 8, _u32s([androidAttrIcon])))
    ..add(
      _chunk(0x0102, 16, [
        ..._u32s([1, none]), // line number, comment
        ..._u32s([none, 1]), // namespace, name
        ..._u16s([20, 20, 1, 0, 0, 0]), // attribute start, size and count
        ..._u32s([none, 0, none]), // namespace, name, raw value
        ..._u16s([8]), // Res_value size
        0, typeReference,
        ..._u32s([_iconResourceId]),
      ]),
    );
  return _chunk(0x0003, 8, body.takeBytes());
}

/// A resource table resolving [_iconResourceId] to `res/icon.png`.
Uint8List _resourceTable() {
  const typeString = 0x03;

  final type = _chunk(0x0201, 36, [
    (_iconResourceId >> 16) & 0xFF, 0, 0, 0, // id, flags, reserved
    ..._u32s([1, 40]), // entry count, entries start
    ..._u32s([16, 0, 0, 0]), // ResTable_config, default configuration
    ..._u32s([0]), // offset of entry 0
    ..._u16s([0, typeString << 8]), // compact entry: key, flags
    ..._u32s([0]), // index of the path in the global string pool
  ]);
  final package = _chunk(0x0200, 12, [
    ..._u32s([_iconResourceId >> 24]),
    ...type,
  ]);
  return _chunk(0x0002, 12, [
    ..._u32s([1]), // package count
    ..._stringPool(['res/icon.png']),
    ...package,
  ]);
}

/// A UTF-8 string pool chunk.
Uint8List _stringPool(List<String> strings) {
  final offsets = <int>[];
  final data = <int>[];
  for (final string in strings) {
    final bytes = utf8.encode(string);
    offsets.add(data.length);
    data.addAll([string.length, bytes.length, ...bytes, 0]);
  }
  while (data.length % 4 != 0) {
    data.add(0);
  }

  const utf8Flag = 0x100;
  return _chunk(0x0001, 28, [
    ..._u32s([strings.length, 0, utf8Flag, 28 + offsets.length * 4, 0]),
    ..._u32s(offsets),
    ...data,
  ]);
}

/// A ResChunk_header of [type] and [headerSize], followed by [rest]: whatever
/// is left of the header, then the body.
Uint8List _chunk(int type, int headerSize, List<int> rest) =>
    Uint8List.fromList([
      ..._u16s([type, headerSize]),
      ..._u32s([8 + rest.length]),
      ...rest,
    ]);

Uint8List _u16s(List<int> values) {
  final data = ByteData(values.length * 2);
  for (final (i, value) in values.indexed) {
    data.setUint16(i * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _u32s(List<int> values) {
  final data = ByteData(values.length * 4);
  for (final (i, value) in values.indexed) {
    data.setUint32(i * 4, value, Endian.little);
  }
  return data.buffer.asUint8List();
}
