import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/app_icon_cache.dart';
import '../theme/app_theme.dart';

/// An Android package's launcher icon, as [AppIconCache] already holds it —
/// for package pickers outside the Apps pane, such as the Logs filter
/// suggestions.
///
/// Read-only: it never fetches. An icon exists only once the Apps pane has
/// pulled that package's APK, on any device in any session; until then, and
/// for values that are not packages at all (`system_server`, `/system/bin/…`),
/// [fallback] shows instead. A package's first lookup is one small file read;
/// after that the cache answers from memory, so a reopened dropdown paints its
/// icons in the first frame.
class const PackageIcon({
  super.key,

  /// A package or process name. A process suffix (`com.app:remote`) is dropped
  /// before the lookup, since icons are cached per package.
  required final String packageName,

  /// Edge of the square, before the app zoom is applied.
  required final double size,

  /// Shown, centred in the same square, while there is no icon.
  required final Widget fallback,

  /// The cache to read; [AppIconCache.instance] unless a test substitutes one.
  final AppIconCache? cache,
}) extends StatefulWidget {
  static final RegExp _packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  /// The package [value] names, or null when it can't be one — so native
  /// processes and kernel threads never cost a disk lookup.
  @visibleForTesting
  static String? packageOf(String value) {
    var name = value.trim();
    final colon = name.indexOf(':');
    if (colon >= 0) name = name.substring(0, colon);
    return _packagePattern.hasMatch(name) ? name : null;
  }

  @override
  State<PackageIcon> createState() => _PackageIconState();
}

class _PackageIconState extends State<PackageIcon> {
  Uint8List? _bytes;

  AppIconCache get _cache => widget.cache ?? AppIconCache.instance;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PackageIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // List rows are reused by index, so the same state can be handed another
    // package when the suggestions narrow.
    if (oldWidget.packageName != widget.packageName ||
        oldWidget.cache != widget.cache) {
      _resolve();
    }
  }

  void _resolve() {
    final package = PackageIcon.packageOf(widget.packageName);
    _bytes = package == null ? null : _cache.peek(package);
    if (package == null || _bytes != null) return;
    _cache.load(package).then((bytes) {
      if (!mounted || bytes == null) return;
      if (PackageIcon.packageOf(widget.packageName) != package) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = context.scaled(widget.size);
    final fallback = SizedBox.square(
      dimension: size,
      child: Center(child: widget.fallback),
    );
    final bytes = _bytes;
    if (bytes == null) return fallback;
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        cacheWidth: decodeSize,
        cacheHeight: decodeSize,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
