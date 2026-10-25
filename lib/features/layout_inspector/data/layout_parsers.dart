import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:xml/xml.dart';

import 'layout_snapshot.dart';

/// Parses `uiautomator dump`'s XML into a one-window snapshot.
///
/// `adb exec-out uiautomator dump /dev/tty` prints the XML and then
/// `UI hierchary dumped to: /dev/tty` on the same stream; anything after
/// `</hierarchy>` is dropped. [displaySize] comes from the screenshot taken
/// alongside, since the dump only carries the rotation. Throws a
/// [FormatException] when there is no hierarchy in [output], which is what
/// `ERROR: could not get idle state.` looks like.
LayoutSnapshot parseUiAutomatorDump(
  String output, {
  required Size displaySize,
  Uint8List? screenshot,
  required DateTime capturedAt,
  Duration elapsed = Duration.zero,
}) {
  final start = output.indexOf('<?xml');
  final end = output.lastIndexOf('</hierarchy>');
  if (start < 0 || end < 0) {
    final message = output.trim();
    throw FormatException(
      message.isEmpty ? 'uiautomator printed nothing' : message,
    );
  }
  final document = XmlDocument.parse(
    output.substring(start, end + '</hierarchy>'.length),
  );
  final hierarchy = document.rootElement;
  final rotation = int.tryParse(hierarchy.getAttribute('rotation') ?? '') ?? 0;

  final nodes = hierarchy.childElements
      .where((element) => element.name.local == 'node')
      .toList();
  LayoutNode? root;
  if (nodes.length == 1) {
    root = _xmlNode(nodes.single, '0');
  } else if (nodes.isNotEmpty) {
    // Several top-level nodes: hang them under one window-sized root.
    final children = [
      for (var i = 0; i < nodes.length; i++) _xmlNode(nodes[i], '0.$i'),
    ];
    root = LayoutNode(
      key: '0',
      className: 'window',
      bounds: Offset.zero & displaySize,
      children: children,
    );
  }
  return LayoutSnapshot(
    windows: [
      LayoutWindow(
        id: 0,
        type: 'application',
        active: true,
        bounds: root?.bounds ?? Offset.zero & displaySize,
        root: root,
      ),
    ],
    displaySize: displaySize,
    rotation: rotation,
    screenshot: screenshot,
    capturedAt: capturedAt,
    source: LayoutSource.uiautomator,
    elapsed: elapsed,
  );
}

LayoutNode _xmlNode(XmlElement element, String key) {
  String? attribute(String name) {
    final value = element.getAttribute(name);
    return value == null || value.isEmpty ? null : value;
  }

  const booleanFlags = {
    'checkable': 'checkable',
    'checked': 'checked',
    'clickable': 'clickable',
    'enabled': 'enabled',
    'focusable': 'focusable',
    'focused': 'focused',
    'scrollable': 'scrollable',
    'long-clickable': 'longClickable',
    'password': 'password',
    'selected': 'selected',
  };
  final children = element.childElements
      .where((child) => child.name.local == 'node')
      .toList();
  return LayoutNode(
    key: key,
    className: attribute('class') ?? 'node',
    packageName: attribute('package'),
    resourceId: attribute('resource-id'),
    text: attribute('text'),
    contentDescription: attribute('content-desc'),
    hint: attribute('hint'),
    bounds: _parseXmlBounds(attribute('bounds')),
    flags: {
      for (final MapEntry(:key, :value) in booleanFlags.entries)
        if (element.getAttribute(key) == 'true') value,
      // uiautomator dumps only what is on screen; say so, so the flags read
      // the same as the helper's.
      'visible',
    },
    children: [
      for (var i = 0; i < children.length; i++)
        _xmlNode(children[i], '$key.$i'),
    ],
  );
}

/// `[0,66][1080,2214]` → a rect.
Rect _parseXmlBounds(String? bounds) {
  final match = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]')
      .firstMatch(bounds ?? '');
  if (match == null) return Rect.zero;
  return Rect.fromLTRB(
    double.parse(match.group(1)!),
    double.parse(match.group(2)!),
    double.parse(match.group(3)!),
    double.parse(match.group(4)!),
  );
}

/// Parses the helper's `snapshot` result (inspector_helper/, `Main.java`).
LayoutSnapshot parseHelperSnapshot(
  Map<String, Object?> result, {
  required DateTime capturedAt,
  Duration elapsed = Duration.zero,
}) {
  final display = (result['display'] as Map?)?.cast<String, Object?>() ?? {};
  final windows = [
    for (final window in (result['windows'] as List? ?? const []))
      (window as Map).cast<String, Object?>(),
  ];
  // Top-most first: the order a tap reaches windows in.
  windows.sort(
    (a, b) => ((b['layer'] as num?) ?? 0).compareTo((a['layer'] as num?) ?? 0),
  );
  final screenshot = result['screenshot'];
  return LayoutSnapshot(
    windows: [
      for (var i = 0; i < windows.length; i++) _helperWindow(windows[i], i),
    ],
    displaySize: Size(
      ((display['width'] as num?) ?? 0).toDouble(),
      ((display['height'] as num?) ?? 0).toDouble(),
    ),
    rotation: (display['rotation'] as num?)?.toInt() ?? 0,
    densityDpi: (display['density'] as num?)?.toInt(),
    screenshot: screenshot is String ? base64Decode(screenshot) : null,
    capturedAt: capturedAt,
    source: LayoutSource.helper,
    elapsed: elapsed,
  );
}

LayoutWindow _helperWindow(Map<String, Object?> json, int index) {
  final root = json['root'];
  return LayoutWindow(
    id: (json['id'] as num?)?.toInt() ?? index,
    type: json['type'] as String? ?? 'unknown',
    title: json['title'] as String?,
    layer: (json['layer'] as num?)?.toInt() ?? 0,
    active: json['active'] == true,
    focused: json['focused'] == true,
    bounds: _parseJsonBounds(json['bounds']),
    root: root is Map
        ? _helperNode(root.cast<String, Object?>(), '$index')
        : null,
  );
}

LayoutNode _helperNode(Map<String, Object?> json, String key) {
  final children = json['children'] as List? ?? const [];
  return LayoutNode(
    key: key,
    className: json['class'] as String? ?? 'node',
    packageName: json['package'] as String?,
    resourceId: json['resourceId'] as String?,
    text: json['text'] as String?,
    contentDescription: json['contentDesc'] as String?,
    hint: json['hint'] as String?,
    stateDescription: json['stateDesc'] as String?,
    paneTitle: json['paneTitle'] as String?,
    bounds: _parseJsonBounds(json['bounds']),
    flags: {...?(json['flags'] as List?)?.cast<String>()},
    children: [
      for (var i = 0; i < children.length; i++)
        _helperNode((children[i] as Map).cast<String, Object?>(), '$key.$i'),
    ],
  );
}

Rect _parseJsonBounds(Object? bounds) {
  if (bounds is! List || bounds.length != 4) return Rect.zero;
  final values = [for (final value in bounds) (value as num).toDouble()];
  return Rect.fromLTRB(values[0], values[1], values[2], values[3]);
}

/// A PNG's width and height, read from its IHDR chunk; null for anything
/// that isn't a PNG.
Size? pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return Size(data.getUint32(16).toDouble(), data.getUint32(20).toDouble());
}
