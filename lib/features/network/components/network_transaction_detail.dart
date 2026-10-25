import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/network_copy.dart';
import '../data/network_timeline.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_body_view.dart';
import 'network_presentation.dart';
import '../../../presentation/components/context_menu.dart';
import '../../../presentation/components/snack_bars.dart';
import '../../../utils/timestamp_utils.dart';
import '../../../presentation/components/hover_builder.dart';

/// One exchange in full, in DevTools' tabs: Headers (a general summary, then
/// each side's headers), Payload (query parameters and the request body),
/// Response (the body, and the server's original when an override replaced
/// it) and Timing. Bodies are fetched when their tab opens.
///
/// [onClose] puts a close button before the tabs, for the side-by-side
/// layout; the stacked layout closes from the pane header instead.
class const NetworkTransactionDetail({
  super.key,
  required final NetworkController controller,
  required final NetworkEntry entry,
  final VoidCallback? onClose,
}) extends StatefulWidget {
  @override
  State<NetworkTransactionDetail> createState() =>
      _NetworkTransactionDetailState();
}

class _NetworkTransactionDetailState extends State<NetworkTransactionDetail> {
  NetworkController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tab = controller.detailTab;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: context.scaled(34),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              if (widget.onClose case final onClose?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AppIconButton(
                    tooltip: 'Close (Esc)',
                    icon: Icons.close,
                    iconSize: 16,
                    padding: 4,
                    onPressed: onClose,
                  ),
                )
              else
                const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final value in NetworkDetailTab.values)
                        _TabButton(
                          label: _tabLabel(value),
                          selected: value == tab,
                          onTap: () =>
                              setState(() => controller.detailTab = value),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (tab) {
            NetworkDetailTab.headers => _HeadersTab(
              controller: controller,
              entry: widget.entry,
            ),
            NetworkDetailTab.payload => _PayloadTab(
              controller: controller,
              entry: widget.entry,
            ),
            NetworkDetailTab.response => _ResponseTab(
              controller: controller,
              entry: widget.entry,
            ),
            NetworkDetailTab.timing => _TimingTab(entry: widget.entry),
          },
        ),
      ],
    );
  }

  String _tabLabel(NetworkDetailTab tab) => switch (tab) {
    NetworkDetailTab.headers => 'Headers',
    NetworkDetailTab.payload => 'Payload',
    NetworkDetailTab.response => 'Response',
    NetworkDetailTab.timing => 'Timing',
  };
}

class const _TabButton({
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered && !selected
                  ? cs.onSurface.withValues(alpha: 0.06)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: selected ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? cs.onSurface : tokens.secondaryTextColor,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Headers ─────────────────────────────────────────────────────────────

class const _HeadersTab({
  required final NetworkController controller,
  required final NetworkEntry entry,
}) extends StatefulWidget {
  @override
  State<_HeadersTab> createState() => _HeadersTabState();
}

class _HeadersTabState extends State<_HeadersTab> {
  /// What the user has selected with the mouse, for the row menus' "Copy
  /// selection".
  String? _selection;

  @override
  Widget build(BuildContext context) {
    final tokens = context.eaglyTheme;
    final transaction = widget.entry.transaction;
    final request = transaction.request;
    final response = transaction.response;
    final override = transaction.override;
    final source = widget.controller.sourceOf(widget.entry.key);
    final elapsed = transaction.elapsed;
    final started = transaction.startedAt;

    final general = [
      NetworkHeader('Request URL', request.url),
      NetworkHeader('Request method', request.method),
      NetworkHeader('Status', statusDescription(transaction)),
      if (request.protocol case final protocol?)
        NetworkHeader('Protocol', protocol),
      if (started != null) NetworkHeader('Started', formatTimeOfDay(started)),
      if (elapsed != null) NetworkHeader('Duration', formatElapsed(elapsed)),
      if (response?.tlsVersion case final tls?) NetworkHeader('TLS', tls),
      if (response?.cipherSuite case final cipher?)
        NetworkHeader('Cipher suite', cipher),
      if (transaction.adapter case final adapter?)
        NetworkHeader('HTTP client', adapter),
      if (source != null) NetworkHeader('Captured by', source.label),
    ];

    return SelectionArea(
      onSelectionChanged: (content) => _selection = content?.plainText,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (transaction.error case final error?)
            _Notice(
              icon: Icons.error_outline,
              color: tokens.errorColor,
              text: error,
            ),
          if (override != null)
            _Notice(
              icon: Icons.edit_note,
              color: tokens.warningColor,
              text: override.originalResponseCode == null
                  ? 'Rewritten by an Inspektor override.'
                  : 'Rewritten by an Inspektor override; the server '
                        'answered ${override.originalResponseCode}.',
            ),
          _Section(
            title: 'General',
            copyText: headersText(general),
            child: _HeaderTable(
              headers: general,
              selection: () => _selection,
              statusColor: statusColor(context, transaction),
            ),
          ),
          if (response != null)
            _Section(
              title: 'Response headers',
              count: response.headers.length,
              copyText: headersText(response.headers),
              child: _HeaderTable(
                headers: response.headers,
                selection: () => _selection,
                onFilter: (name) => widget.controller.setFilter(
                  widget.controller.filter.withTerm(
                    'has-response-header:${name.toLowerCase()}',
                  ),
                ),
              ),
            ),
          _Section(
            title: 'Request headers',
            count: request.headers.length,
            copyText: headersText(request.headers),
            child: _HeaderTable(
              headers: request.headers,
              selection: () => _selection,
              onFilter: (name) => widget.controller.setFilter(
                widget.controller.filter.withTerm(
                  'has-request-header:${name.toLowerCase()}',
                ),
              ),
            ),
          ),
          if (override?.originalResponseHeaders case final original?)
            _Section(
              title: 'Original response headers',
              count: original.length,
              initiallyExpanded: false,
              copyText: headersText(original),
              child: _HeaderTable(
                headers: original,
                selection: () => _selection,
              ),
            ),
          if (override?.originalRequestHeaders case final original?)
            _Section(
              title: 'Original request headers',
              count: original.length,
              initiallyExpanded: false,
              copyText: headersText(original),
              child: _HeaderTable(
                headers: original,
                selection: () => _selection,
              ),
            ),
        ],
      ),
    );
  }
}

class const _Notice({
  required final IconData icon,
  required final Color color,
  required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: context.scaled(16), color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible section: a clickable title with a chevron and a count, and
/// a copy button for the whole section.
class const _Section({
  required final String title,
  required final Widget child,
  final int? count,
  final String? copyText,
  final bool initiallyExpanded = true,
}) extends StatefulWidget {
  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded = widget.initiallyExpanded;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
              color: _hovered ? cs.onSurface.withValues(alpha: 0.04) : null,
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: context.scaled(18),
                      color: tokens.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 2),
                  SelectionContainer.disabled(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (widget.count case final count?) ...[
                    const SizedBox(width: 6),
                    SelectionContainer.disabled(
                      child: Text(
                        '$count',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.tertiaryTextColor,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.copyText case final text? when text.isNotEmpty)
                    AnimatedOpacity(
                      opacity: _hovered ? 1 : 0.0,
                      duration: const Duration(milliseconds: 120),
                      child: AppIconButton(
                        tooltip: 'Copy ${widget.title.toLowerCase()}',
                        icon: Icons.copy,
                        iconSize: 14,
                        padding: 4,
                        onPressed: () => copyWithToast(
                          context,
                          text,
                          'Copied ${widget.title.toLowerCase()}.',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Name/value rows. Each highlights on hover and has a right-click menu to
/// copy it, and — given [onFilter] — to filter the list to exchanges that
/// carry the same header.
class const _HeaderTable({
  required final List<NetworkHeader> headers,
  required final String? Function() selection,
  final ValueChanged<String>? onFilter,
  final Color? statusColor,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) return const NetworkPlaceholder('None');
    return LayoutBuilder(
      builder: (context, constraints) {
        final nameWidth = (constraints.maxWidth * 0.32).clamp(90.0, 240.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final header in headers)
              _HeaderRow(
                header: header,
                nameWidth: nameWidth,
                selection: selection,
                onFilter: onFilter,
                valueColor: header.name == 'Status' ? statusColor : null,
              ),
          ],
        );
      },
    );
  }
}

class const _HeaderRow({
  required final NetworkHeader header,
  required final double nameWidth,
  required final String? Function() selection,
  final ValueChanged<String>? onFilter,
  final Color? valueColor,
}) extends StatefulWidget {
  @override
  State<_HeaderRow> createState() => _HeaderRowState();
}

enum _HeaderAction { copySelection, copyValue, copyLine, copyName, filter }

class _HeaderRowState extends State<_HeaderRow> {
  bool _hovered = false;

  Future<void> _showMenu(Offset position) async {
    final header = widget.header;
    final selected = widget.selection();
    final result = await showMenu<_HeaderAction>(
      context: context,
      position: menuPositionAt(position),
      items: [
        if (selected != null && selected.isNotEmpty) ...[
          const PopupMenuItem(
            value: _HeaderAction.copySelection,
            child: MenuRow(Icons.content_copy, 'Copy selection'),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: _HeaderAction.copyValue,
          child: MenuRow(Icons.copy, 'Copy value'),
        ),
        const PopupMenuItem(
          value: _HeaderAction.copyLine,
          child: MenuRow(Icons.notes, 'Copy name and value'),
        ),
        const PopupMenuItem(
          value: _HeaderAction.copyName,
          child: MenuRow(Icons.title, 'Copy name'),
        ),
        if (widget.onFilter != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _HeaderAction.filter,
            child: MenuRow(
              Icons.filter_alt_outlined,
              'Show only requests with ${header.name}',
            ),
          ),
        ],
      ],
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _HeaderAction.copySelection:
        await copyWithToast(context, selected!, 'Copied selection.');
      case _HeaderAction.copyValue:
        await copyWithToast(context, header.value, 'Copied value.');
      case _HeaderAction.copyLine:
        await copyWithToast(context, '$header', 'Copied header.');
      case _HeaderAction.copyName:
        await copyWithToast(context, header.name, 'Copied name.');
      case _HeaderAction.filter:
        widget.onFilter?.call(header.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final style = tokens.monoStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      height: 1.45,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _hovered
                ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.nameWidth,
                child: Text(
                  widget.header.name,
                  style: style.copyWith(
                    color: tokens.secondaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.header.value,
                  style: style.copyWith(color: widget.valueColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Payload ─────────────────────────────────────────────────────────────

class const _PayloadTab({
  required final NetworkController controller,
  required final NetworkEntry entry,
}) extends StatefulWidget {
  @override
  State<_PayloadTab> createState() => _PayloadTabState();
}

class _PayloadTabState extends State<_PayloadTab> {
  String? _selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.entry.transaction.request;
    final uri = request.uri;
    final query = uri == null || !uri.hasQuery
        ? const <NetworkHeader>[]
        : [
            for (final MapEntry(:key, :value) in uri.queryParametersAll.entries)
              for (final item in value) NetworkHeader(key, item),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (query.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.3,
            ),
            child: SelectionArea(
              onSelectionChanged: (content) => _selection = content?.plainText,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _Section(
                    title: 'Query string parameters',
                    count: query.length,
                    copyText: uri!.query,
                    child: _HeaderTable(
                      headers: query,
                      selection: () => _selection,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (query.isNotEmpty)
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: request.body == NetworkBodyState.empty && query.isNotEmpty
              ? const NetworkPlaceholder('No request body')
              : NetworkBodyView(
                  key: ValueKey((widget.entry.key, NetworkBodyPart.request)),
                  controller: widget.controller,
                  entryKey: widget.entry.key,
                  part: NetworkBodyPart.request,
                  state: request.body,
                  contentType: request.contentType,
                ),
        ),
      ],
    );
  }
}

// ── Response ────────────────────────────────────────────────────────────

class const _ResponseTab({
  required final NetworkController controller,
  required final NetworkEntry entry,
}) extends StatefulWidget {
  @override
  State<_ResponseTab> createState() => _ResponseTabState();
}

class _ResponseTabState extends State<_ResponseTab> {
  bool _original = false;

  @override
  Widget build(BuildContext context) {
    final transaction = widget.entry.transaction;
    final response = transaction.response;
    if (response == null) {
      return NetworkPlaceholder(switch (transaction.state) {
        NetworkTransactionState.pending => 'Waiting for the response…',
        _ =>
          'No response${transaction.error == null ? '' : ': ${transaction.error}'}',
      });
    }
    final original = transaction.override?.originalResponseBody;
    final hasOriginal = original != null;
    final showOriginal = hasOriginal && _original;
    final part = showOriginal
        ? NetworkBodyPart.originalResponse
        : NetworkBodyPart.response;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasOriginal)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Overridden'),
                    tooltip: 'What the app received',
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Original'),
                    tooltip: 'What the server sent before the override',
                  ),
                ],
                selected: {showOriginal},
                onSelectionChanged: (value) =>
                    setState(() => _original = value.first),
              ),
            ),
          ),
        Expanded(
          child: NetworkBodyView(
            key: ValueKey((widget.entry.key, part)),
            controller: widget.controller,
            entryKey: widget.entry.key,
            part: part,
            state: showOriginal ? original : response.body,
            contentType: response.contentType,
          ),
        ),
      ],
    );
  }
}

// ── Timing ──────────────────────────────────────────────────────────────

class const _TimingTab({required final NetworkEntry entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final transaction = entry.transaction;
    final span = spanOf(transaction);
    final elapsed = transaction.elapsed;
    final timings = transaction.timings;
    final phases = <(String, Duration)>[
      for (final (label, duration) in [
        ('DNS lookup', timings?.dns),
        ('Initial connection', timings?.connect),
        ('TLS handshake', timings?.tls),
        ('Request sent', timings?.send),
        ('Waiting for the server', timings?.wait),
        ('Content download', timings?.receive),
      ])
        if (duration != null) (label, duration),
    ];
    final total =
        elapsed ??
        phases.fold<Duration>(Duration.zero, (sum, phase) => sum + phase.$2);

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (span != null)
            Text(
              'Started at ${formatTimeOfDay(span.start)}'
              '${span.end == null ? ', still running' : ', finished at ${formatTimeOfDay(span.end!)}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.secondaryTextColor,
              ),
            ),
          const SizedBox(height: 12),
          if (phases.isEmpty)
            const NetworkPlaceholder(
              'This source reports no phases (DNS, connect, TLS, waiting, '
              'download), only the total.',
            )
          else
            ..._phaseRows(context, phases, total),
          const SizedBox(height: 8),
          Divider(color: theme.colorScheme.outlineVariant),
          Row(
            children: [
              Text('Total', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                elapsed == null ? '–' : formatElapsed(elapsed),
                style: tokens.monoStyle.copyWith(
                  fontSize: theme.textTheme.bodySmall?.fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _phaseRows(
    BuildContext context,
    List<(String, Duration)> phases,
    Duration total,
  ) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final totalUs = total.inMicroseconds <= 0 ? 1 : total.inMicroseconds;
    final colors = [
      const Color(0xFF26A69A),
      const Color(0xFFFFA726),
      const Color(0xFFAB47BC),
      const Color(0xFF9E9E9E),
      const Color(0xFF42A5F5),
      const Color(0xFF66BB6A),
    ];
    var offset = 0;
    return [
      for (final (index, (label, duration)) in phases.indexed)
        Builder(
          builder: (context) {
            final start = offset / totalUs;
            final width = duration.inMicroseconds / totalUs;
            offset += duration.inMicroseconds;
            return Tooltip(
              message: '$label: ${formatElapsed(duration)}',
              waitDuration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: context.scaled(150),
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: context.scaled(12),
                        child: CustomPaint(
                          painter: _PhasePainter(
                            start: start.clamp(0.0, 1.0),
                            width: width.clamp(0.0, 1.0),
                            color: colors[index % colors.length],
                            track: theme.colorScheme.onSurface.withValues(
                              alpha: 0.05,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: context.scaled(72),
                      child: Text(
                        formatElapsed(duration),
                        textAlign: TextAlign.end,
                        style: tokens.monoStyle.copyWith(
                          fontSize: theme.textTheme.bodySmall?.fontSize,
                          color: tokens.secondaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }
}

class _PhasePainter extends CustomPainter {
  _PhasePainter({
    required this.start,
    required this.width,
    required this.color,
    required this.track,
  });

  final double start;
  final double width;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final left = start * size.width;
    final barWidth = (width * size.width).clamp(2.0, size.width - left);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, barWidth, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PhasePainter old) =>
      old.start != start || old.width != width || old.color != color;
}
