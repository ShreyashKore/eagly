import 'package:flutter/widgets.dart';

import '../../utils/text_search_pattern.dart';
import 'data/terminal_line.dart';

/// One match in the scrollback: [range] within [line]'s text.
class const TerminalMatch(final TerminalLine line, final TextSearchMatch range);

/// Find in one terminal tab's scrollback: the query and its options, every
/// match, and which one is current.
///
/// Matches are collected again whenever the scrollback changes ([refresh]),
/// which is cheap next to the scrollback's line cap. The current match is
/// remembered by its line rather than its index, so output arriving below it —
/// or old lines falling off the front — leaves it where it is.
class TerminalFind(final List<TerminalLine> Function() _lines)
    extends ChangeNotifier {
  this {
    query.addListener(_onQueryChanged);
  }

  final TextEditingController query = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'Terminal find');

  bool _isOpen = false;
  bool _caseSensitive = false;
  bool _regex = false;
  String _searched = '';
  TextSearchPattern _pattern = TextSearchPattern(
    query: '',
    caseSensitive: false,
    wholeWord: false,
    regex: false,
  );
  List<TerminalMatch> _matches = const [];
  Map<TerminalLine, List<TextSearchMatch>> _byLine = const {};
  int _current = -1;
  int _moves = 0;

  bool get isOpen => _isOpen;
  bool get caseSensitive => _caseSensitive;
  bool get regex => _regex;

  /// The query is a regex that doesn't compile.
  bool get isInvalid => _pattern.hasError;

  List<TerminalMatch> get matches => _matches;

  /// Index into [matches] of the current one, or -1 when there are none.
  int get currentIndex => _current;

  TerminalMatch? get current => _current < 0 ? null : _matches[_current];

  /// Bumped whenever the current match moves because of the search itself — a
  /// new query, ↵, ⇧↵ — and not when output arrives. The view scrolls to the
  /// current match when this changes.
  int get moves => _moves;

  /// The matches in [line], in order; empty when it has none.
  List<TextSearchMatch> matchesIn(TerminalLine line) =>
      _byLine[line] ?? const [];

  void open() {
    if (!_isOpen) {
      _isOpen = true;
      _search();
      notifyListeners();
    }
    query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: query.text.length,
    );
    focusNode.requestFocus();
  }

  /// Hides the bar and its highlights. The query is kept for next time.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    _searched = '';
    _setMatches(const [], -1);
    notifyListeners();
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _search();
    notifyListeners();
  }

  void toggleRegex() {
    _regex = !_regex;
    _search();
    notifyListeners();
  }

  void next() => _step(1);

  void previous() => _step(-1);

  /// Collects the matches again after the scrollback changed, keeping the
  /// current one if its line is still there.
  void refresh() {
    if (!_isOpen || !_pattern.isActive) return;
    final kept = current;
    final matches = _collect();
    var index = kept == null
        ? -1
        : matches.indexWhere(
            (m) =>
                identical(m.line, kept.line) &&
                m.range.start == kept.range.start,
          );
    if (index < 0 && matches.isNotEmpty) index = matches.length - 1;
    _setMatches(matches, index);
    notifyListeners();
  }

  void _onQueryChanged() {
    // The controller also notifies for caret moves and selection.
    if (!_isOpen || query.text == _searched) return;
    _search();
    notifyListeners();
  }

  /// Searches from scratch. The current match starts at the last one — the
  /// one nearest the latest output, where a terminal is read from.
  void _search() {
    _searched = query.text;
    _pattern = TextSearchPattern(
      query: query.text,
      caseSensitive: _caseSensitive,
      wholeWord: false,
      regex: _regex,
    );
    final matches = _collect();
    _setMatches(matches, matches.length - 1);
    _moves++;
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    _current = (_current + delta) % _matches.length;
    _moves++;
    notifyListeners();
  }

  List<TerminalMatch> _collect() {
    if (!_pattern.isActive || _pattern.hasError) return const [];
    return [
      for (final line in _lines())
        for (final range in _pattern.allMatches(line.text))
          TerminalMatch(line, range),
    ];
  }

  void _setMatches(List<TerminalMatch> matches, int current) {
    _matches = matches;
    _current = current;
    final byLine = Map<TerminalLine, List<TextSearchMatch>>.identity();
    for (final match in matches) {
      (byLine[match.line] ??= []).add(match.range);
    }
    _byLine = byLine;
  }

  @override
  void dispose() {
    query.removeListener(_onQueryChanged);
    query.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
