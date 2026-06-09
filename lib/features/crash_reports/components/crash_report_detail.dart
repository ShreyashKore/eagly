import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../presentation/components/search_highlight.dart';
import '../../../presentation/components/text_search_bar.dart';
import '../../../utils/text_search_pattern.dart';
import '../crash_report_controller.dart';
import '../utils.dart';

class CrashReportDetail extends StatefulWidget {
  const CrashReportDetail({super.key, required this.controller});

  final CrashReportController controller;

  @override
  State<CrashReportDetail> createState() => _CrashReportDetailState();
}

class _CrashReportDetailState extends State<CrashReportDetail> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _searchVisible = false;
  TextSearchConfig _search = const TextSearchConfig();
  int _currentMatch = 0;
  int _matchCount = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchVisible = true);
  }

  void _closeSearch() {
    setState(() => _searchVisible = false);
  }

  void _onSearchChanged(TextSearchConfig config) {
    setState(() {
      _search = config;
      _currentMatch = 0;
    });
  }

  void _nextMatch() {
    if (_matchCount == 0) return;
    setState(() => _currentMatch = (_currentMatch + 1) % _matchCount);
  }

  void _previousMatch() {
    if (_matchCount == 0) return;
    setState(
      () => _currentMatch = (_currentMatch - 1 + _matchCount) % _matchCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final report = controller.selectedReport!;
    final body = controller.selectedReportBody;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.fileName, style: theme.textTheme.bodySmall),
                    Text(
                      CrashReportUtils.formatTimestamp(report.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy report',
                onPressed: body == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: body));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Crash report copied to clipboard.'),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy, size: 18),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        Expanded(
          child: body == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(context, body),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, String body) {
    final pattern = TextSearchPattern.fromConfig(_search);
    final matches = _searchVisible && pattern.isActive && pattern.isValid
        ? pattern.allMatches(body)
        : const <TextSearchMatch>[];
    _matchCount = matches.length;
    final currentMatch = matches.isEmpty
        ? -1
        : _currentMatch.clamp(0, matches.length - 1);

    final bodyStyle = context.eaglyTheme.logBodyStyle.copyWith(height: 1.4);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
      },
      child: Focus(
        child: Stack(
          children: [
            Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText.rich(
                  TextSpan(
                    style: bodyStyle,
                    children: buildSearchHighlightSpans(
                      context: context,
                      text: body,
                      style: bodyStyle,
                      matches: matches,
                      currentMatchIndex: currentMatch < 0 ? null : currentMatch,
                    ),
                  ),
                ),
              ),
            ),
            if (_searchVisible)
              Positioned(
                top: 12,
                right: 12,
                child: TextSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  search: _search,
                  hasError: pattern.hasError,
                  errorText: pattern.errorText,
                  hintText: 'Search in report...',
                  onSearchChanged: _onSearchChanged,
                  onSearchOptionsChanged: _onSearchChanged,
                  onNext: _nextMatch,
                  onPrevious: _previousMatch,
                  onClose: _closeSearch,
                  totalMatches: matches.length,
                  currentMatch: matches.isEmpty ? 0 : currentMatch + 1,
                ),
              )
            else
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.small(
                  heroTag: 'crash-report-search',
                  tooltip: 'Search in report (Ctrl/Cmd+F)',
                  onPressed: _openSearch,
                  child: const Icon(Icons.search),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
