/// A small subsequence-based fuzzy matcher (VS Code / fzf style): every
/// character of [query] must appear in [text], in order, but not necessarily
/// contiguously — so "cp" matches "Command Palette" and "rlddv" matches
/// "Reload Devices". Returns a score where higher is a better match, or
/// `null` when [query] doesn't match [text] at all.
///
/// Consecutive-character runs and word-boundary starts score higher, so a
/// tight/prefix-ish match outranks a scattered one for the same query.
int? fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = text.toLowerCase();

  var score = 0;
  var searchFrom = 0;
  var consecutive = 0;

  for (var i = 0; i < q.length; i++) {
    final foundAt = t.indexOf(q[i], searchFrom);
    if (foundAt == -1) return null;

    if (foundAt == searchFrom) {
      consecutive++;
      score += 3 + consecutive; // reward runs of consecutive characters
    } else {
      consecutive = 0;
      score += 1;
    }
    if (foundAt == 0 || !_isWordChar(t[foundAt - 1])) {
      score += 4; // reward matches that start a word
    }

    searchFrom = foundAt + 1;
  }

  if (t.startsWith(q)) score += 10;
  // Penalize matches spread across a lot of the target for the same query.
  score -= ((searchFrom - q.length) ~/ 4).clamp(0, 20);

  return score;
}

bool _isWordChar(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x61 && code <= 0x7a); // a-z
}
