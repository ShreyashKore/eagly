import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/presentation/models/log_view_mode.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  test('selectedLogLevel defaults to verbose', () {
    expect(PreferencesService.selectedLogLevel, LogLevel.verbose);
    expect(PreferencesService.filterViewMode, LogFilterViewMode.classic);
    expect(
      PreferencesService.defaultTabSettings.selectedLogLevel,
      LogLevel.verbose,
    );
    expect(
      PreferencesService.defaultTabSettings.filterViewMode,
      LogFilterViewMode.classic,
    );
  });

  test(
    'selectedLogLevel setter persists the canonical preference key',
    () async {
      PreferencesService.selectedLogLevel = LogLevel.error;

      final prefs = await SharedPreferences.getInstance();
      expect(PreferencesService.selectedLogLevel, LogLevel.error);
      expect(prefs.getString('selectedLogLevel'), LogLevel.error.code);
    },
  );

  test('filterViewMode setter persists the canonical preference key', () async {
    PreferencesService.filterViewMode = LogFilterViewMode.inline;

    final prefs = await SharedPreferences.getInstance();
    expect(PreferencesService.filterViewMode, LogFilterViewMode.inline);
    expect(prefs.getString('filterViewMode'), LogFilterViewMode.inline.name);
  });

  group('recent log files', () {
    test('defaults to empty and seeds the listenable', () {
      expect(PreferencesService.recentLogFiles, isEmpty);
      expect(PreferencesService.recentLogFilesListenable.value, isEmpty);
    });

    test('adds most-recent first and updates the listenable', () async {
      await PreferencesService.addRecentLogFile('/logs/a.log');
      await PreferencesService.addRecentLogFile('/logs/b.log');

      expect(PreferencesService.recentLogFiles, ['/logs/b.log', '/logs/a.log']);
      expect(PreferencesService.recentLogFilesListenable.value, [
        '/logs/b.log',
        '/logs/a.log',
      ]);
    });

    test(
      're-adding an existing path moves it to the front (deduped)',
      () async {
        await PreferencesService.addRecentLogFile('/logs/a.log');
        await PreferencesService.addRecentLogFile('/logs/b.log');
        await PreferencesService.addRecentLogFile('/logs/a.log');

        expect(PreferencesService.recentLogFiles, [
          '/logs/a.log',
          '/logs/b.log',
        ]);
      },
    );

    test('caps the list at 10 entries', () async {
      for (var i = 0; i < 13; i++) {
        await PreferencesService.addRecentLogFile('/logs/file_$i.log');
      }

      final recent = PreferencesService.recentLogFiles;
      expect(recent, hasLength(10));
      expect(recent.first, '/logs/file_12.log');
      expect(recent.last, '/logs/file_3.log');
    });

    test('blank paths are ignored', () async {
      await PreferencesService.addRecentLogFile('   ');
      expect(PreferencesService.recentLogFiles, isEmpty);
    });

    test('removeRecentLogFile drops the entry and persists', () async {
      await PreferencesService.addRecentLogFile('/logs/a.log');
      await PreferencesService.addRecentLogFile('/logs/b.log');

      await PreferencesService.removeRecentLogFile('/logs/a.log');

      expect(PreferencesService.recentLogFiles, ['/logs/b.log']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recentLogFiles'), contains('b.log'));
      expect(prefs.getString('recentLogFiles'), isNot(contains('a.log')));
    });
  });
}
