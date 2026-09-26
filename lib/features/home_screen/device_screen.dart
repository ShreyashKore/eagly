import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../presentation/components/drop_zone.dart';
import '../../session/device_session_controller.dart';
import '../../utils/log_feedback.dart';
import '../logs/log_feature_view.dart';
import 'components/device_screen_content.dart';
import 'components/drop_overlay.dart';
import 'feature_rail.dart';

/// The screen shown for the selected device tab: the feature rail on the far
/// left, then the open feature panes (Logs always, Mirror alongside when open).
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.session,
    required this.appMemoryBytesListenable,
    required this.onOpenSettings,
  });

  final DeviceSessionController session;
  final ValueListenable<int> appMemoryBytesListenable;
  final VoidCallback onOpenSettings;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _isDragOver = false;

  /// The pane-level zone under the pointer during a drag; while one is set it
  /// owns the drop, and the screen-wide overlay stays hidden.
  DropZoneHandle? _hoveredZone;

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleInstallApp() async {
    final result = await widget.session.installAppFromPicker();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatAppInstallMessage(result));
  }

  void _handleDragMove(DropEventDetails details) {
    final zone = DropZone.at(context, details.globalPosition);
    // Updates arrive per pointer move; rebuild only on an actual change.
    if (_isDragOver && zone == _hoveredZone) return;
    _hoveredZone?.isHovered = false;
    zone?.isHovered = true;
    setState(() {
      _isDragOver = true;
      _hoveredZone = zone;
    });
  }

  void _handleDragExit(DropEventDetails _) {
    _hoveredZone?.isHovered = false;
    setState(() {
      _isDragOver = false;
      _hoveredZone = null;
    });
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    // Resolved from the drop point itself rather than the last hover, which
    // lags a fast drag by up to one update.
    final zone = DropZone.at(context, detail.globalPosition);
    _hoveredZone?.isHovered = false;
    if (mounted) {
      setState(() {
        _isDragOver = false;
        _hoveredZone = null;
      });
    }
    final paths = detail.files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;
    if (zone != null) return zone.drop(paths);

    final result = await widget.session.handleDroppedPaths(paths);
    if (!mounted || result == null) return;
    final message = result.message;
    if (message != null) _showSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The device-less "Imported Logs" workspace has no device features (mirror,
    // files, install, …) — show just the log viewer, full-width.
    if (widget.session.isImportedWorkspace) {
      return DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: LogFeatureView(
          logManager: widget.session.logSessionManager,
          session: widget.session,
          appMemoryBytesListenable: widget.appMemoryBytesListenable,
          onClose: () {},
        ),
      );
    }

    return DropTarget(
      onDragEntered: _handleDragMove,
      onDragUpdated: _handleDragMove,
      onDragExited: _handleDragExit,
      onDragDone: _handleDrop,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Stack(
          children: [
            Row(
              children: [
                FeatureRail(
                  session: widget.session,
                  onInstall: _handleInstallApp,
                  onOpenSettings: widget.onOpenSettings,
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.session,
                    builder: (context, _) => DeviceScreenContent(
                      session: widget.session,
                      appMemoryBytesListenable: widget.appMemoryBytesListenable,
                    ),
                  ),
                ),
              ],
            ),
            // IgnorePointer: the overlay must not hide the panes beneath it
            // from DropZone.at's hit test.
            if (_isDragOver && _hoveredZone == null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DropOverlay(session: widget.session),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
