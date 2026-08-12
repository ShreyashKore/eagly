import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  Future<void> _handleDrop(DropDoneDetails detail) async {
    if (mounted) setState(() => _isDragOver = false);
    final paths = detail.files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) return;

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
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
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
            if (_isDragOver)
              Positioned.fill(child: DropOverlay(session: widget.session)),
          ],
        ),
      ),
    );
  }
}
