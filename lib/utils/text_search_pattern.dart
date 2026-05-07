import 'package:flutter/foundation.dart';

@immutable
class TextSearchMatch {
  const TextSearchMatch({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;
}

@immutable
class TextSearchPattern {
  factory TextSearchPattern({
    required String query,
    required bool caseSensitive,
    required bool wholeWord,
    required bool regex,
  }) {
    if (query.isEmpty) {
      return TextSearchPattern._(
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
      );
    }

    if (!regex && !wholeWord) {
      return TextSearchPattern._(
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
      );
    }

    try {
      final source = regex ? query : RegExp.escape(query);
      final wrappedSource = wholeWord ? '\\b(?:$source)\\b' : source;
      return TextSearchPattern._(
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
        regExp: RegExp(
          wrappedSource,
          caseSensitive: caseSensitive,
          multiLine: true,
        ),
      );
    } on FormatException catch (error) {
      return TextSearchPattern._(
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
        errorText: error.message,
      );
    }
  }

  const TextSearchPattern._({
    required this.query,
    required this.caseSensitive,
    required this.wholeWord,
    required this.regex,
    this.regExp,
    this.errorText,
  });

  final String query;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;
  final RegExp? regExp;
  final String? errorText;

  bool get isActive => query.isNotEmpty;
  bool get isValid => errorText == null;
  bool get hasError => errorText != null;

  TextSearchMatch? firstMatch(String text) {
    final matches = allMatches(text);
    return matches.isEmpty ? null : matches.first;
  }

  bool matches(String text) => firstMatch(text) != null;

  List<TextSearchMatch> allMatches(String text) {
    if (!isActive || hasError) {
      return const <TextSearchMatch>[];
    }

    final regExp = this.regExp;
    if (regExp != null) {
      final results = <TextSearchMatch>[];
      for (final match in regExp.allMatches(text)) {
        if (match.start == match.end) {
          continue;
        }
        results.add(TextSearchMatch(start: match.start, end: match.end));
      }
      return results;
    }

    final needle = caseSensitive ? query : query.toLowerCase();
    final haystack = caseSensitive ? text : text.toLowerCase();
    if (needle.isEmpty) {
      return const <TextSearchMatch>[];
    }

    final results = <TextSearchMatch>[];
    var start = 0;
    while (start < haystack.length) {
      final index = haystack.indexOf(needle, start);
      if (index == -1) {
        break;
      }
      results.add(TextSearchMatch(start: index, end: index + needle.length));
      start = index + needle.length;
    }
    return results;
  }
}

