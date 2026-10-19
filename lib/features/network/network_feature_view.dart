import 'package:flutter/material.dart';

import '../../presentation/components/app_icon_button.dart';
import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import '../../utils/utils.dart';
import 'components/network_transaction_detail.dart';
import 'components/network_transaction_list.dart';
import 'network_controller.dart';
import 'services/network_file_service.dart';
import 'services/network_source.dart';

/// Network feature pane: HTTP exchanges captured from the device's apps, or
/// opened from a HAR file. A list, and one exchange in detail when picked.
/// See docs/NETWORK_INSPECTOR.md.
class const NetworkFeatureView({
  super.key,
  required final NetworkController controller,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

  @override
  State<NetworkFeatureView> createState() => _NetworkFeatureViewState();
}

class _NetworkFeatureViewState extends FeatureViewState<NetworkFeatureView> {
  bool _exporting = false;

  NetworkController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  Future<void> _openHar() async {
    final path = await NetworkFileService.pickHarToOpen();
    if (path == null) return;
    try {
      await controller.openHar(path);
    } catch (error) {
      showSnackBar(
        'Could not open ${extractFileName(path)}: ${describeError(error)}',
      );
    }
  }

  Future<void> _exportHar() async {
    final path = await NetworkFileService.pickHarSavePath(
      NetworkFileService.suggestedHarName(
        controller.device.displayName,
        DateTime.now(),
      ),
    );
    if (path == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final count = controller.entries.length;
      await controller.exportHar(path);
      showSnackBar('Exported $count requests to ${extractFileName(path)}');
    } catch (error) {
      showSnackBar('Could not export: ${describeError(error)}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    final selected = controller.selected;
    final uri = selected?.transaction.request.uri;

    return FeaturePane(
      header: FeatureViewHeader(
        title: selected == null
            ? 'Network'
            : (uri?.pathSegments.lastWhere(
                    (segment) => segment.isNotEmpty,
                    orElse: () => uri.host,
                  ) ??
                  selected.transaction.request.url),
        closeTooltip: 'Close network pane',
        onClose: widget.onClose,
        leading: selected == null
            ? null
            : AppIconButton(
                tooltip: 'Back to list',
                onPressed: () => controller.select(null),
                icon: Icons.arrow_back,
              ),
        actions: [
          ToolbarAction(
            icon: Icons.file_open_outlined,
            label: 'Open HAR file',
            onPressed: _openHar,
          ),
          ToolbarAction(
            icon: Icons.save_alt,
            label: 'Export as HAR',
            onPressed: controller.isEmpty || _exporting ? null : _exportHar,
            iconOverride: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          ToolbarAction(
            icon: Icons.block,
            label: 'Clear',
            tooltip: 'Clear the list. Nothing is deleted on the device.',
            onPressed: controller.isEmpty ? null : controller.clear,
          ),
        ],
      ),
      body: switch (selected) {
        final entry? => NetworkTransactionDetail(
          key: ValueKey(entry.key),
          controller: controller,
          entry: entry,
        ),
        null when controller.isEmpty => CenteredStateMessage(
          icon: Icons.http,
          title: 'No network traffic yet',
          description:
              'Apps that ship Inspektor will show their requests here. '
              'You can also open a HAR file exported from Inspektor, a '
              'browser or a proxy.',
          footer: FilledButton.icon(
            onPressed: _openHar,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Open HAR file'),
          ),
        ),
        null => NetworkTransactionList(controller: controller),
      },
      statusBar: controller.isEmpty
          ? null
          : FeatureStatusBar(
              children: [
                Text('${controller.entries.length} requests'),
                for (final source in controller.sources)
                  Text(_describeSource(source)),
              ],
            ),
    );
  }

  String _describeSource(NetworkSourceInfo source) => switch (source.status) {
    NetworkSourceStatus.connecting => '${source.label}: connecting…',
    NetworkSourceStatus.live => '${source.label}: live',
    NetworkSourceStatus.ended => source.message ?? source.label,
    NetworkSourceStatus.failed =>
      '${source.label}: ${source.message ?? 'failed'}',
  };
}
