import 'package:eagly/features/app_log/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppLogger.global.clear();
  });

  tearDown(() {
    AppLogger.global.clear();
  });

  test(
    'scoped loggers submit to the shared root store with inherited defaults',
    () {
      final repositoryLogger = AppLogger(source: 'DeviceRepository');
      final sessionLogger = repositoryLogger.scoped(
        sessionTag: 'workspace-tab-1',
      );

      sessionLogger.error(
        'Failed to refresh devices',
        detail: 'adb unavailable',
      );

      expect(AppLogger.global.entries, hasLength(1));
      final entry = AppLogger.global.entries.single;
      expect(entry.source, 'DeviceRepository');
      expect(entry.sessionTag, 'workspace-tab-1');
      expect(entry.message, 'Failed to refresh devices');
      expect(entry.detail, 'adb unavailable');
    },
  );

  test(
    'entriesWhere and latestEntry can filter to session-scoped errors only',
    () {
      final root = AppLogger.global;
      final tabLogger = AppLogger(
        source: 'DeviceSessionService',
        sessionTag: 'tab-a',
      );
      final otherLogger = AppLogger(
        source: 'DeviceSessionService',
        sessionTag: 'tab-b',
      );

      tabLogger.info('Log stream started');
      tabLogger.error('Tool error while streaming logs', detail: 'broken pipe');
      otherLogger.error('Other workspace error', detail: 'permission denied');

      final tabErrors = root.entriesWhere(
        sessionTag: 'tab-a',
        errorsOnly: true,
      );
      expect(tabErrors, hasLength(1));
      expect(tabErrors.single.message, 'Tool error while streaming logs');

      final latestTabError = root.latestEntry(
        sessionTag: 'tab-a',
        errorsOnly: true,
      );
      expect(latestTabError, isNotNull);
      expect(latestTabError!.detail, 'broken pipe');

      expect(root.hasEntries(sessionTag: 'tab-a', errorsOnly: true), isTrue);
      expect(root.hasEntries(sessionTag: 'missing', errorsOnly: true), isFalse);
    },
  );
}
