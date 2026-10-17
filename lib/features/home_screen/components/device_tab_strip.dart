import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../../session/device_session_manager.dart';
import 'device_tab.dart';

class const DeviceTabStrip({super.key, required this.manager})
    extends StatefulWidget {
  final DeviceSessionManager manager;

  /// How wide each tab is, given the width its content [wanted] and the
  /// [available] strip. A tab never grows past what it needs (nor past
  /// [DeviceTab.maxWidth]); when they don't all fit, the widest give way
  /// first, down to one shared cap that is never below [DeviceTab.minWidth] —
  /// past that the strip scrolls.
  @visibleForTesting
  static List<double> fitTabWidths(List<double> wanted, double available) {
    final widths = [
      for (final width in wanted)
        math.min(width.ceilToDouble(), DeviceTab.maxWidth),
    ];
    final total = widths.fold(0.0, (sum, width) => sum + width);
    if (!available.isFinite || total <= available) return widths;

    // Tabs narrower than an even share of what is left keep their width; the
    // rest split the remainder.
    var remaining = available;
    var count = widths.length;
    var cap = 0.0;
    for (final width in [...widths]..sort()) {
      if (width * count <= remaining) {
        remaining -= width;
        count--;
      } else {
        cap = remaining / count;
        break;
      }
    }
    cap = math.max(cap.floorToDouble(), DeviceTab.minWidth);
    return [for (final width in widths) math.min(width, cap)];
  }

  /// Labels that more than one open device tab would show, so those tabs add
  /// what tells them apart — needed under [Device.shortNames], where tabs
  /// otherwise show the model alone.
  @visibleForTesting
  static Set<String> ambiguousLabels(Iterable<DeviceSessionController> tabs) {
    final seen = <String>{};
    final ambiguous = <String>{};
    for (final tab in tabs) {
      if (tab.isImportedWorkspace) continue;
      final label = tab.device.displayLabel.primary;
      if (!seen.add(label)) ambiguous.add(label);
    }
    return ambiguous;
  }

  @override
  State<DeviceTabStrip> createState() => _DeviceTabStripState();
}

class _DeviceTabStripState extends State<DeviceTabStrip> {
  final _scrollController = ScrollController();

  /// Session ids we've already rendered, so a tab only plays its entrance +
  /// highlight-wave the first time it appears (i.e. when a device connects).
  final Set<String> _seenIds = {};
  bool _firstBuild = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    return ListenableBuilder(
      listenable: manager,
      // Each session too: a device's label can change after its tab opens
      // (adb describes it a moment later), and that can make two tabs match.
      builder: (context, _) => ListenableBuilder(
        listenable: Listenable.merge(manager.sessions),
        builder: (context, _) => _buildTabs(manager),
      ),
    );
  }

  Widget _buildTabs(DeviceSessionManager manager) {
    final sessions = manager.sessions;

    // Figure out which tabs are appearing for the first time. On the very
    // first build everything is "already there" (no entrance), so only
    // devices that connect later animate in.
    final currentIds = {for (final s in sessions) s.id};
    _seenIds.removeWhere((id) => !currentIds.contains(id));
    final freshIds = <String>{};
    for (final s in sessions) {
      if (_seenIds.add(s.id) && !_firstBuild) freshIds.add(s.id);
    }
    _firstBuild = false;

    final ambiguous = DeviceTabStrip.ambiguousLabels(sessions);

    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerSignal: _onPointerSignal,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          child: _TabRow(
            available: constraints.maxWidth,
            children: [
              for (final session in sessions)
                DeviceTab(
                  key: ValueKey(session.id),
                  session: session,
                  disambiguate: ambiguous.contains(
                    session.device.displayLabel.primary,
                  ),
                  selected: manager.selectedId == session.id,
                  animateIn: freshIds.contains(session.id),
                  onSelect: () => manager.select(session.id),
                  onReload: manager.canReload(session.id)
                      ? () => manager.reload(session.id)
                      : null,
                  onClose: manager.canClose(session.id)
                      ? () => manager.close(session.id)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Layout ───────────────────────────────────────────────────────────────

/// Lays the tabs out left to right at [DeviceTabStrip.fitTabWidths], each
/// stretched to the strip's height. Tabs get a *loose* width so the
/// entrance animation can still shrink one below it.
class const _TabRow({required this.available, required super.children})
    extends MultiChildRenderObjectWidget {
  /// Width of the visible strip; the row itself may be wider and scroll.
  final double available;

  @override
  _RenderTabRow createRenderObject(BuildContext context) =>
      _RenderTabRow(available);

  @override
  void updateRenderObject(BuildContext context, _RenderTabRow renderObject) {
    renderObject.available = available;
  }
}

class _TabRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTabRow(this._available)
    extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabRowParentData> {
  double _available;
  set available(double value) {
    if (value == _available) return;
    _available = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabRowParentData) {
      child.parentData = _TabRowParentData();
    }
  }

  @override
  void performLayout() {
    final tabs = getChildrenAsList();
    final height = constraints.maxHeight;
    final widths = DeviceTabStrip.fitTabWidths([
      for (final tab in tabs) tab.getMaxIntrinsicWidth(height),
    ], _available);

    var x = 0.0;
    var tallest = 0.0;
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      tab.layout(
        BoxConstraints(
          maxWidth: widths[i],
          minHeight: height.isFinite ? height : 0,
          maxHeight: height,
        ),
        parentUsesSize: true,
      );
      (tab.parentData! as _TabRowParentData).offset = Offset(x, 0);
      x += tab.size.width;
      tallest = math.max(tallest, tab.size.height);
    }
    size = constraints.constrain(Size(x, tallest));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final wanted = [
      for (final tab in getChildrenAsList()) tab.getMaxIntrinsicWidth(height),
    ];
    return DeviceTabStrip.fitTabWidths(
      wanted,
      double.infinity,
    ).fold(0.0, (sum, width) => sum + width);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => getChildrenAsList().fold(
    0.0,
    (tallest, tab) =>
        math.max(tallest, tab.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
