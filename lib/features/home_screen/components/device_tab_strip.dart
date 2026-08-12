import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../session/device_session_manager.dart';
import 'device_tab.dart';

class DeviceTabStrip extends StatefulWidget {
  const DeviceTabStrip({super.key, required this.manager});

  final DeviceSessionManager manager;

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
      builder: (context, _) {
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

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scrollController,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final session in sessions)
                  DeviceTab(
                    key: ValueKey(session.id),
                    session: session,
                    selected: manager.selectedId == session.id,
                    animateIn: freshIds.contains(session.id),
                    onSelect: () => manager.select(session.id),
                    onClose: manager.canClose(session.id)
                        ? () => manager.close(session.id)
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
