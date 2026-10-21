import 'package:eagly/features/terminal/data/terminal_line.dart';
import 'package:eagly/features/terminal/terminal_find.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<TerminalLine> lines;
  late TerminalFind find;

  TerminalLine out(String text) => TerminalLine(TerminalLineKind.stdout, text);

  setUp(() {
    lines = [out('alpha beta'), out('gamma'), out('beta beta')];
    find = TerminalFind(() => lines);
  });

  tearDown(() => find.dispose());

  void search(String query) {
    find.open();
    find.query.text = query;
  }

  test('a new search starts on the match nearest the latest output', () {
    search('beta');

    expect(find.matches, hasLength(3));
    expect(find.currentIndex, 2);
    expect(identical(find.current!.line, lines[2]), isTrue);
    expect(find.current!.range.start, 5);
  });

  test('next and previous wrap around', () {
    search('beta');
    final moves = find.moves;

    find.next();
    expect(find.currentIndex, 0);
    find.previous();
    expect(find.currentIndex, 2);
    expect(find.moves, moves + 2);
  });

  test('matches are listed per line', () {
    search('beta');

    expect(find.matchesIn(lines[0]).map((m) => m.start), [6]);
    expect(find.matchesIn(lines[1]), isEmpty);
    expect(find.matchesIn(lines[2]).map((m) => m.start), [0, 5]);
  });

  test('new output keeps the current match and does not move the view', () {
    search('beta');
    find.next(); // the first line's match
    final moves = find.moves;

    lines.add(out('beta again'));
    find.refresh();

    expect(find.matches, hasLength(4));
    expect(identical(find.current!.line, lines[0]), isTrue);
    expect(find.moves, moves);
  });

  test('a current match whose line fell off the front falls back', () {
    search('beta');
    find.next();

    lines.removeAt(0);
    find.refresh();

    expect(find.matches, hasLength(2));
    expect(find.currentIndex, 1);
  });

  test('case sensitivity is off until toggled', () {
    search('BETA');
    expect(find.matches, hasLength(3));

    find.toggleCaseSensitive();
    expect(find.matches, isEmpty);
    expect(find.currentIndex, -1);
    expect(find.current, isNull);
  });

  test('a regex that does not compile finds nothing and says so', () {
    find.toggleRegex();
    search('(beta');

    expect(find.isInvalid, isTrue);
    expect(find.matches, isEmpty);

    find.query.text = 'b.ta';
    expect(find.isInvalid, isFalse);
    expect(find.matches, hasLength(3));
  });

  test('closing clears the highlights but keeps the query', () {
    search('gamma');
    find.close();

    expect(find.isOpen, isFalse);
    expect(find.matches, isEmpty);
    expect(find.query.text, 'gamma');

    // Output arriving while closed doesn't search.
    lines.add(out('gamma'));
    find.refresh();
    expect(find.matches, isEmpty);

    find.open();
    expect(find.matches, hasLength(2));
  });
}
