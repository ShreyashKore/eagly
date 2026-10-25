import 'dart:io';

import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/tab_list_manager.dart';
import 'package:eagly/utils/file_dialog_directory.dart';
import 'package:eagly/utils/timestamp_utils.dart';
import 'package:eagly/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pluralize', () {
    test('keeps the noun for one and adds an s otherwise', () {
      expect(pluralize(1, 'file'), '1 file');
      expect(pluralize(0, 'file'), '0 files');
      expect(pluralize(3, 'file'), '3 files');
    });

    test('takes an irregular plural', () {
      expect(pluralize(2, 'entry', plural: 'entries'), '2 entries');
      expect(pluralize(1, 'entry', plural: 'entries'), '1 entry');
    });
  });

  test('shellQuote survives embedded single quotes', () {
    expect(shellQuote('a b'), "'a b'");
    expect(shellQuote("it's"), r"'it'\''s'");
  });

  test('firstNonBlank trims and skips blank values', () {
    expect(firstNonBlank('  Pixel  ', 'other'), 'Pixel');
    expect(firstNonBlank('   ', ' other '), 'other');
    expect(firstNonBlank(null, null), isNull);
    expect(firstNonBlank(''), isNull);
  });

  test(
    'parseColonSeparated keeps keyed values and splits on the first colon',
    () {
      expect(
        parseColonSeparated(
          'DeviceName: Phone\n'
          '  Nested: value\n'
          'Url: http://x:1\n'
          ': no key\n'
          'NoValue:\n'
          'no separator',
        ),
        {'DeviceName': 'Phone', 'Nested': 'value', 'Url': 'http://x:1'},
      );
    },
  );

  group('time formatting', () {
    final time = DateTime(2026, 3, 4, 5, 6, 7, 89);

    test('formatTimeOfDay cuts down to the precision', () {
      expect(formatTimeOfDay(time), '05:06:07.089');
      expect(
        formatTimeOfDay(time, precision: TimePrecision.second),
        '05:06:07',
      );
      expect(formatTimeOfDay(time, precision: TimePrecision.minute), '05:06');
    });

    test('formatDateTime puts the date first', () {
      expect(formatDateTime(time), '2026-03-04 05:06:07.089');
      expect(
        formatDateTime(time, precision: TimePrecision.minute),
        '2026-03-04 05:06',
      );
    });

    test('fileNameTimestamp has no separators a file system rejects', () {
      expect(fileNameTimestamp(time), '20260304-050607');
    });
  });

  group('FileDialogDirectory', () {
    late Directory temp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.init();
      temp = await Directory.systemTemp.createTemp('eagly_dialog_dir');
    });

    tearDown(() => temp.delete(recursive: true));

    test('remembers the folder holding a picked file', () async {
      final file = File('${temp.path}${Platform.pathSeparator}log.txt')
        ..writeAsStringSync('x');

      await FileDialogDirectory.rememberParentOf(file.path);

      expect(FileDialogDirectory.initial(), temp.path);
    });

    test('remembers the folder holding a bundle directory', () async {
      final bundle = Directory('${temp.path}${Platform.pathSeparator}A.app')
        ..createSync();

      await FileDialogDirectory.rememberParentOf(bundle.path);

      expect(FileDialogDirectory.initial(), temp.path);
    });

    test('ignores a folder that no longer exists', () async {
      final gone = '${temp.path}${Platform.pathSeparator}gone';

      await FileDialogDirectory.remember(gone);

      expect(PreferencesService.lastFileDialogDirectory, isNull);
      expect(FileDialogDirectory.initial(), isNot(gone));
    });
  });

  group('TabListManager', () {
    test('selects a new tab, keeps a valid selection on close, and disposes '
        'every tab', () {
      final manager = _Tabs();
      final first = _Tab();
      final second = _Tab();
      final third = _Tab();
      manager
        ..add(first)
        ..add(second)
        ..add(third);
      expect(manager.selectedIndex, 2);

      manager.closeTab(2);
      expect(third.disposed, isTrue);
      expect(manager.selectedIndex, 1);

      manager.closeTab(0); // the first tab is permanent here
      expect(manager.tabs, [first, second]);

      manager.dispose();
      expect(first.disposed && second.disposed, isTrue);
    });

    test('does not notify once disposed', () {
      final manager = _Tabs()..add(_Tab());
      var notified = 0;
      manager.addListener(() => notified++);
      manager.selectTab(0); // already selected
      expect(notified, 0);
      manager.dispose();
      // A late async result calling back after dispose must not throw.
      expect(manager.poke, returnsNormally);
    });
  });
}

class _Tab extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Tabs extends TabListManager<_Tab> {
  void add(_Tab tab) => appendTab(tab);

  void poke() => notifyChanged();

  @override
  bool canClose(int index) => index > 0 && index < tabs.length;
}
