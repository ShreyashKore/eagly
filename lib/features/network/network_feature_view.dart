import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/components/app_icon_button.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import '../../presentation/theme/app_theme.dart';
import '../../utils/utils.dart';
import 'components/network_empty_guide.dart';
import 'components/network_filter_bar.dart';
import 'components/network_overview.dart';
import 'components/network_presentation.dart';
import 'components/network_transaction_detail.dart';
import 'components/network_transaction_list.dart';
import 'network_controller.dart';
import 'data/network_transaction.dart';
import 'data/network_transaction_store.dart';
import 'services/network_file_service.dart';
import 'services/network_source.dart';

/// Network feature pane: HTTP exchanges captured from the device's apps, or
/// opened from a HAR file, laid out like DevTools' Network panel: a filter
/// bar, a timeline overview, the request table, and one exchange in detail
/// when picked — beside the list when the pane is wide enough, in its place
/// when not. See docs/NETWORK_INSPECTOR.md.
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
  final FocusNode _filterFocus = FocusNode(debugLabel: 'Network filter');
  final FocusNode _listFocus = FocusNode(debugLabel: 'Network list');

  /// The list's share of the width while an exchange is open beside it.
  double _listFraction = 0.4;

  /// Below this width an open exchange replaces the list instead of sitting
  /// beside it.
  static const double _splitWidth = 720;

  @override
  void dispose() {
    _filterFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _focusFilter() {
    _filterFocus.requestFocus();
  }

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= context.scaled(_splitWidth);
        final selected = controller.selected;
        final stacked = selected != null && !split;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _focusFilter,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _focusFilter,
          },
          child: FeaturePane(
            header: _buildHeader(stacked ? selected : null),
            body: _buildBody(context, selected, stacked: stacked),
            statusBar: controller.isEmpty ? null : _buildStatusBar(context),
          ),
        );
      },
    );
  }

  FeatureViewHeader _buildHeader(NetworkEntry? shownAlone) {
    return FeatureViewHeader(
      title: shownAlone == null ? 'Network' : shortName(shownAlone.transaction),
      closeTooltip: 'Close network pane',
      onClose: widget.onClose,
      leading: shownAlone == null
          ? null
          : AppIconButton(
              tooltip: 'Back to list',
              onPressed: () => controller.select(null),
              icon: Icons.arrow_back,
            ),
      actions: [
        ToolbarAction(
          icon: Icons.view_timeline_outlined,
          label: 'Timeline overview',
          tooltip: controller.showOverview
              ? 'Hide the timeline overview'
              : 'Show the timeline overview',
          isActive: controller.showOverview,
          onPressed: controller.toggleOverview,
        ),
        ToolbarAction(
          icon: Icons.file_open_outlined,
          label: 'Open HAR file',
          dividerBefore: true,
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
    );
  }

  Widget _buildBody(
    BuildContext context,
    NetworkEntry? selected, {
    required bool stacked,
  }) {
    if (controller.isEmpty) {
      return NetworkEmptyGuide(controller: controller, onOpenHar: _openHar);
    }
    final list = NetworkTransactionList(
      controller: controller,
      compact: selected != null && !stacked,
      focusNode: _listFocus,
    );
    // The list keeps one place in the tree whatever is open, so opening an
    // exchange never resets its scroll position or drops a pending menu.
    // Stacked, it stays mounted behind the exchange.
    final listArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetworkFilterBar(controller: controller, focusNode: _filterFocus),
        if (controller.showOverview) NetworkOverview(controller: controller),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final beside = selected != null && !stacked;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: beside ? width * _listFraction : width,
                    child: list,
                  ),
                  if (beside) ...[
                    _SplitHandle(
                      onDrag: (dx) => setState(() {
                        _listFraction = (_listFraction + dx / width).clamp(
                          0.2,
                          0.75,
                        );
                      }),
                    ),
                    Expanded(
                      child: NetworkTransactionDetail(
                        key: ValueKey(selected.key),
                        controller: controller,
                        entry: selected,
                        onClose: () {
                          controller.select(null);
                          _listFocus.requestFocus();
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: stacked,
          child: TickerMode(enabled: !stacked, child: listArea),
        ),
        if (stacked)
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  controller.select(null),
            },
            child: NetworkTransactionDetail(
              key: ValueKey(selected!.key),
              controller: controller,
              entry: selected,
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final all = controller.entries;
    final visible = controller.visibleEntries;
    final filtered = controller.filter.isActive;
    var transferred = 0;
    DateTime? first;
    DateTime? last;
    for (final entry in visible) {
      final transaction = entry.transaction;
      transferred += transaction.response?.size ?? 0;
      final start = transaction.startedAt;
      if (start == null) continue;
      final end = transaction.elapsed == null
          ? start
          : start.add(transaction.elapsed!);
      if (first == null || start.isBefore(first)) first = start;
      if (last == null || end.isAfter(last)) last = end;
    }
    final separator = Text(
      '  |  ',
      style: TextStyle(color: context.eaglyTheme.tertiaryTextColor),
    );

    return FeatureStatusBar(
      children: [
        Text(
          filtered
              ? '${visible.length} / ${all.length} requests'
              : '${all.length} requests',
        ),
        separator,
        Tooltip(
          message: 'Response bytes of the requests listed',
          child: Text('${formatBytes(transferred)} received'),
        ),
        if (first != null && last != null) ...[
          separator,
          Tooltip(
            message: 'From the first request\'s start to the last one\'s end',
            child: Text('Span ${formatElapsed(last.difference(first))}'),
          ),
        ],
        const Spacer(),
        for (final source in controller.sources) ...[
          const SizedBox(width: 12),
          _SourceStatus(label: _describeSource(source), status: source.status),
        ],
      ],
    );
  }

  String _describeSource(NetworkSourceInfo source) => switch (source.status) {
    NetworkSourceStatus.connecting => '${source.label}: connecting…',
    NetworkSourceStatus.live => '${source.label}: live',
    NetworkSourceStatus.ended => switch (source.kind) {
      NetworkSourceKind.har => source.message ?? source.label,
      // The app quit or went to the background; it continues on return.
      NetworkSourceKind.inspektor => '${source.label}: disconnected',
    },
    NetworkSourceStatus.failed =>
      '${source.label}: ${source.message ?? 'failed'}',
  };
}

/// One source in the status bar, with a dot for its state.
class const _SourceStatus({
  required final String label,
  required final NetworkSourceStatus status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.eaglyTheme;
    final color = switch (status) {
      NetworkSourceStatus.live => tokens.statusLiveColor,
      NetworkSourceStatus.connecting => tokens.statusPausedColor,
      NetworkSourceStatus.ended => tokens.statusStoppedColor,
      NetworkSourceStatus.failed => tokens.errorColor,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

/// The draggable divider between the list and an open exchange.
class const _SplitHandle({required final ValueChanged<double> onDrag})
    extends StatefulWidget {
  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _active ? 3 : 1,
              color: _active ? cs.primary : cs.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
