import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/network_filter.dart';
import '../data/network_timeline.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_presentation.dart';
import 'network_row_menu.dart';
import '../../../utils/timestamp_utils.dart';

export 'network_presentation.dart' show formatElapsed, statusColor, statusLabel;

/// The Network pane's list of exchanges, like DevTools' request table: status,
/// method, name (path over host), type, size, time and a waterfall, each
/// column sortable from its header. Rows highlight on hover, open on click,
/// and offer copy and filter actions on right-click; ↑/↓ move the selection
/// and Esc closes it.
///
/// [compact] keeps only the status, method and name columns, for the narrow
/// list beside an open exchange.
class const NetworkTransactionList({
  super.key,
  required final NetworkController controller,
  final bool compact = false,
  final FocusNode? focusNode,
}) extends StatefulWidget {
  @override
  State<NetworkTransactionList> createState() => _NetworkTransactionListState();
}

class _NetworkTransactionListState extends State<NetworkTransactionList> {
  final ScrollController _scroll = ScrollController();
  late final FocusNode _ownFocus = FocusNode(debugLabel: 'Network list');

  FocusNode get _focus => widget.focusNode ?? _ownFocus;
  NetworkController get controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _step(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _step(_rowsPerPage);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _step(-_rowsPerPage);
    } else if (key == LogicalKeyboardKey.escape &&
        controller.selected != null) {
      controller.select(null);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int get _rowsPerPage {
    if (!_scroll.hasClients) return 10;
    return (_scroll.position.viewportDimension / _rowExtent(context))
        .floor()
        .clamp(1, 100);
  }

  void _step(int delta) {
    controller.selectAdjacent(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  /// Scrolls just far enough to show the selected row.
  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;
    final key = controller.selected?.key;
    if (key == null) return;
    final index = controller.visibleEntries.indexWhere((e) => e.key == key);
    if (index < 0) return;
    final extent = _rowExtent(context);
    final top = index * extent;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + extent > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (top + extent - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = controller.visibleEntries;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(
          compact: widget.compact,
          width: constraints.maxWidth,
          scale: context.scaled(1),
        );
        final range = _waterfallRange(controller);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderRow(controller: controller, columns: columns),
            Expanded(
              child: entries.isEmpty
                  ? _NoMatches(controller: controller)
                  : Focus(
                      focusNode: _focus,
                      onKeyEvent: _onKey,
                      child: Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          itemExtent: _rowExtent(context),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _Row(
                              key: ValueKey(entry.key),
                              entry: entry,
                              index: index,
                              columns: columns,
                              range: range,
                              selected: entry.key == controller.selected?.key,
                              onTap: () {
                                _focus.requestFocus();
                                controller.select(entry.key);
                              },
                              onContextMenu: (position) {
                                _focus.requestFocus();
                                return showNetworkEntryMenu(
                                  context,
                                  position,
                                  controller: controller,
                                  entry: entry,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

double _rowExtent(BuildContext context) => context.scaled(38);

/// What the waterfall column scales against: the overview's time window when
/// one is picked, else everything the overview draws.
NetworkTimeRange? _waterfallRange(NetworkController controller) {
  if (controller.filter.timeWindow case final window?) {
    return NetworkTimeRange(window.start, window.end);
  }
  return NetworkTimeRange.of(controller.timelineEntries)?.padded();
}

enum _ColumnKind { status, method, name, type, size, time, waterfall }

class const _Column(
  final _ColumnKind kind,
  final String title, {
  final double? width,
  final int flex = 0,
  final NetworkSortColumn? sort,
  final bool alignEnd = false,
  final String tooltip = '',
});

List<_Column> _columnsFor({
  required bool compact,
  required double width,
  required double scale,
}) {
  final status = _Column(
    _ColumnKind.status,
    'Status',
    width: 64 * scale,
    sort: NetworkSortColumn.status,
    tooltip: 'Response status code',
  );
  final method = _Column(
    _ColumnKind.method,
    'Method',
    width: 64 * scale,
    sort: NetworkSortColumn.method,
  );
  const name = _Column(
    _ColumnKind.name,
    'Name',
    flex: 3,
    sort: NetworkSortColumn.name,
    tooltip: 'Path and query, with the host below',
  );
  if (compact) return [status, method, name];
  final showType = width >= 520 * scale;
  final showWaterfall = width >= 760 * scale;
  return [
    status,
    method,
    name,
    if (showType)
      _Column(
        _ColumnKind.type,
        'Type',
        width: 84 * scale,
        sort: NetworkSortColumn.type,
        tooltip: 'Response content type',
      ),
    _Column(
      _ColumnKind.size,
      'Size',
      width: 72 * scale,
      sort: NetworkSortColumn.size,
      alignEnd: true,
      tooltip: 'Response body size',
    ),
    _Column(
      _ColumnKind.time,
      'Time',
      width: 72 * scale,
      sort: NetworkSortColumn.time,
      alignEnd: true,
      tooltip: 'Time from request to the end of the response',
    ),
    if (showWaterfall)
      const _Column(
        _ColumnKind.waterfall,
        'Waterfall',
        flex: 2,
        tooltip: 'When each request ran, on the overview\'s scale',
      ),
  ];
}

const _cellPadding = EdgeInsets.symmetric(horizontal: 6);

Widget _cell(_Column column, Widget child) {
  final padded = Padding(padding: _cellPadding, child: child);
  if (column.width case final width?) {
    return SizedBox(width: width, child: padded);
  }
  return Expanded(flex: column.flex, child: padded);
}

class const _HeaderRow({
  required final NetworkController controller,
  required final List<_Column> columns,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: context.scaled(28),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final column in columns)
            _cell(column, _HeaderCell(controller: controller, column: column)),
        ],
      ),
    );
  }
}

class const _HeaderCell({
  required final NetworkController controller,
  required final _Column column,
}) extends StatefulWidget {
  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  bool _hovered = false;

  /// Ascending, then descending, then back to capture order.
  void _cycleSort() {
    final column = widget.column.sort;
    if (column == null) return;
    final current = widget.controller.sort;
    widget.controller.setSort(switch (current) {
      NetworkSort(column: final c, descending: false) when c == column =>
        NetworkSort(column, descending: true),
      NetworkSort(column: final c, descending: true) when c == column => null,
      _ => NetworkSort(column),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final column = widget.column;
    final sort = widget.controller.sort;
    final sorted = sort != null && sort.column == column.sort;
    final sortable = column.sort != null;
    final label = Text(
      column.title,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: theme.textTheme.labelSmall?.copyWith(
        color: sorted || _hovered
            ? theme.colorScheme.onSurface
            : tokens.secondaryTextColor,
        fontWeight: FontWeight.w600,
      ),
    );
    final content = Row(
      mainAxisAlignment: column.alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(child: label),
        if (sorted)
          Icon(
            sort.descending ? Icons.arrow_downward : Icons.arrow_upward,
            size: context.scaled(12),
            color: theme.colorScheme.primary,
          ),
      ],
    );
    if (!sortable) {
      return Tooltip(
        message: column.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: Align(alignment: Alignment.centerLeft, child: content),
      );
    }
    return Tooltip(
      message: [
        if (column.tooltip.isNotEmpty) column.tooltip,
        sorted
            ? (sort.descending
                  ? 'Click to restore capture order'
                  : 'Click to sort descending')
            : 'Click to sort',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cycleSort,
          child: Align(alignment: Alignment.centerLeft, child: content),
        ),
      ),
    );
  }
}

class const _Row({
  super.key,
  required final NetworkEntry entry,
  required final int index,
  required final List<_Column> columns,
  required final NetworkTimeRange? range,
  required final bool selected,
  required final VoidCallback onTap,

  /// Shows the row's menu; completes when it closes.
  required final Future<void> Function(Offset position) onContextMenu,
}) extends StatefulWidget {
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  /// The row's menu is open: it stays highlighted so it is clear what the
  /// menu acts on. Right-click does not open the exchange.
  bool _menuOpen = false;

  Future<void> _showMenu(Offset position) async {
    setState(() => _menuOpen = true);
    try {
      await widget.onContextMenu(position);
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    final transaction = widget.entry.transaction;
    final error = isErrorTransaction(transaction);
    final small = theme.textTheme.bodySmall;
    final metaStyle = small?.copyWith(color: tokens.secondaryTextColor);
    final mono = tokens.monoStyle.copyWith(fontSize: small?.fontSize);

    final background = widget.selected
        ? cs.primary.withValues(alpha: 0.16)
        : _hovered || _menuOpen
        ? cs.onSurface.withValues(alpha: 0.06)
        : widget.index.isOdd
        ? cs.onSurface.withValues(alpha: 0.025)
        : null;

    Widget content(_Column column) => switch (column.kind) {
      _ColumnKind.status => Tooltip(
        message: statusDescription(transaction),
        waitDuration: const Duration(milliseconds: 400),
        child: Text(
          statusLabel(transaction),
          style: mono.copyWith(
            fontWeight: FontWeight.w600,
            color: statusColor(context, transaction),
          ),
        ),
      ),
      _ColumnKind.method => Text(
        transaction.request.method,
        overflow: TextOverflow.ellipsis,
        style: mono,
      ),
      _ColumnKind.name => _NameCell(
        transaction: transaction,
        error: error,
        selected: widget.selected,
      ),
      _ColumnKind.type => Text(
        shortContentType(transaction.response?.contentType),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: metaStyle,
      ),
      _ColumnKind.size => _SizeCell(transaction: transaction, style: metaStyle),
      _ColumnKind.time => _TimeCell(transaction: transaction, style: metaStyle),
      _ColumnKind.waterfall => _WaterfallCell(
        transaction: transaction,
        range: widget.range,
      ),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.only(left: 4, right: 6),
          decoration: BoxDecoration(
            color: background,
            // Always 2 px, so selecting a row does not shift its columns.
            border: Border(
              left: BorderSide(
                color: widget.selected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              for (final column in widget.columns)
                _cell(
                  column,
                  Align(
                    alignment: column.alignEnd
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: content(column),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _NameCell({
  required final NetworkTransaction transaction,
  required final bool error,
  required final bool selected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final uri = transaction.request.uri;
    final host = uri?.host ?? '';
    return Tooltip(
      message: transaction.request.url,
      waitDuration: const Duration(milliseconds: 600),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (transaction.override != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.edit_note,
                    size: context.scaled(14),
                    color: tokens.warningColor,
                    semanticLabel: 'Overridden',
                  ),
                ),
              Expanded(
                child: Text(
                  displayPath(transaction),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: theme.textTheme.bodyMedium?.fontSize,
                    color: error ? tokens.errorColor : null,
                  ),
                ),
              ),
            ],
          ),
          if (host.isNotEmpty)
            Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tokens.tertiaryTextColor,
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }
}

class const _SizeCell({
  required final NetworkTransaction transaction,
  required final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = transaction.response?.size;
    final requestSize = transaction.request.size;
    if (size == null) {
      return Text(
        transaction.state == NetworkTransactionState.pending ? '…' : '–',
        style: style,
      );
    }
    return Tooltip(
      message: [
        'Response: $size bytes',
        if (requestSize != null) 'Request: $requestSize bytes',
        if (transaction.response?.body == NetworkBodyState.truncated)
          'The app captured only part of the body',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 400),
      child: Text(formatBytes(size), maxLines: 1, style: style),
    );
  }
}

class const _TimeCell({
  required final NetworkTransaction transaction,
  required final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final elapsed = transaction.elapsed;
    final started = transaction.startedAt;
    if (elapsed == null) {
      return Text(
        transaction.state == NetworkTransactionState.pending ? 'Pending' : '–',
        style: style,
      );
    }
    final timings = transaction.timings;
    return Tooltip(
      message: [
        if (started != null) 'Started ${formatTimeOfDay(started)}',
        if (timings?.wait case final wait?)
          'Waiting for the server: ${formatElapsed(wait)}',
        if (timings?.receive case final receive?)
          'Receiving: ${formatElapsed(receive)}',
        'Total: ${formatElapsed(elapsed)}',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 400),
      child: Text(formatElapsed(elapsed), maxLines: 1, style: style),
    );
  }
}

/// A bar for when the exchange ran, on [range]'s scale. A pending exchange
/// runs to the end of the range.
class const _WaterfallCell({
  required final NetworkTransaction transaction,
  required final NetworkTimeRange? range,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final range = this.range;
    final span = spanOf(transaction);
    if (range == null || span == null) return const SizedBox.shrink();
    final color = networkBarColor(context, transaction);
    return SizedBox.expand(
      child: CustomPaint(
        painter: _WaterfallPainter(
          start: range.fractionOf(span.start),
          end: range.fractionOf(span.end ?? range.end),
          color: color,
          pending: span.end == null,
          guide: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// The bar color for [transaction] in the waterfall and the overview.
Color networkBarColor(BuildContext context, NetworkTransaction transaction) {
  final tokens = context.eaglyTheme;
  return switch (NetworkStatusClass.of(transaction)) {
    NetworkStatusClass.success => Theme.of(context).colorScheme.primary,
    NetworkStatusClass.redirect => tokens.warningColor,
    NetworkStatusClass.clientError ||
    NetworkStatusClass.serverError ||
    NetworkStatusClass.failed => tokens.errorColor,
    NetworkStatusClass.pending => tokens.tertiaryTextColor,
  };
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.pending,
    required this.guide,
  });

  final double start;
  final double end;
  final Color color;
  final bool pending;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    // Outside a time window the bar is clipped to the column.
    if (end < 0 || start > 1) return;
    final left = (start.clamp(0.0, 1.0)) * size.width;
    final right = (end.clamp(0.0, 1.0)) * size.width;
    final height = 6.0;
    final top = (size.height - height) / 2;
    final rect = Rect.fromLTRB(
      left,
      top,
      (right - left < 2 ? left + 2 : right),
      top + height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = pending ? color.withValues(alpha: 0.5) : color,
    );
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) =>
      old.start != start ||
      old.end != end ||
      old.color != color ||
      old.pending != pending;
}

/// The list's empty state while a filter hides everything.
class const _NoMatches({required final NetworkController controller})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: context.scaled(28),
            color: tokens.tertiaryTextColor,
          ),
          const SizedBox(height: 8),
          Text(
            'No requests match the filter',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => controller.setFilter(NetworkFilter.none),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}
