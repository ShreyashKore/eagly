import 'package:flutter_test/flutter_test.dart';
import 'package:logview/data/log_entry.dart';
import 'package:logview/utils/ios_syslog_parser.dart';

void main() {
  group('IosSyslogParser', () {
    test('groups multi-line syslog entries and normalizes timestamps', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      final logs = <LogEntry>[];
      final lines = <String>[
        'Apr 23 17:09:37.903010 AssetCacheLocatorService[5255] <Debug>: #65bb95e7 [AssetCacheLocatorService.queue] cachedServersForNetworkIdentifiers -> {',
        '    networkIdentifiers =     (',
        '                {',
        '            digest = {length = 32, bytes = 0x1d8fb5e2 db885c3e b017d2f5 975905c1 ... 34c8a741 9d740d68 };',
        '            key = {length = 32, bytes = 0x03b513c1 96e49751 3c732bde c480c8e9 ... 475638f0 5fd07b5d };',
        '        }',
        '    );',
        '    servers =     (',
        '    );',
        '    validUntil = "2026-04-24 04:39:46 +0000";',
        '} validityInterval=61208.097',
        'Apr 23 17:09:37.903030 AssetCacheLocatorService[5255] <Debug>: #65bb95e7 [AssetCacheLocatorService.queue] local cached servers=(',
        ') early hit=YES',
      ];

      for (final line in lines) {
        logs.addAll(parser.addLine(line));
      }
      final trailingEntry = parser.flush();
      if (trailingEntry != null) {
        logs.add(trailingEntry);
      }

      expect(logs, hasLength(2));
      expect(logs.first.timestamp, '2026-04-23 17:09:37.903');
      expect(logs.first.level, 'debug');
      expect(logs.first.tag, 'AssetCacheLocatorService');
      expect(logs.first.packageName, 'AssetCacheLocatorService');
      expect(logs.first.processName, 'AssetCacheLocatorService');
      expect(
        logs.first.message,
        contains('cachedServersForNetworkIdentifiers -> {'),
      );
      expect(
        logs.first.message,
        contains('validUntil = "2026-04-24 04:39:46 +0000";'),
      );
      expect(logs.first.message, contains('\n    servers =     ('));
      expect(
        logs.last.message,
        '#65bb95e7 [AssetCacheLocatorService.queue] local cached servers=(\n) early hit=YES',
      );
    });

    test('captures process labels with spaces and parentheses', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      final logs = <LogEntry>[];

      logs.addAll(
        parser.addLine(
          'Apr 23 17:10:40.588177 novio (R14)(Flutter)[5727] <Notice>: flutter: ╟ x-xss-protection: [1; mode=block]',
        ),
      );
      final trailingEntry = parser.flush();
      if (trailingEntry != null) {
        logs.add(trailingEntry);
      }

      expect(logs, hasLength(1));
      expect(logs.single.timestamp, '2026-04-23 17:10:40.588');
      expect(logs.single.level, 'default');
      expect(logs.single.tag, 'novio (R14)(Flutter)');
      expect(logs.single.packageName, 'novio');
      expect(logs.single.processName, 'novio (R14)(Flutter)');
      expect(
        logs.single.message,
        'flutter: ╟ x-xss-protection: [1; mode=block]',
      );
    });

    test('decodes cat-v style meta escapes emitted by piped iOS syslog', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 26));

      parser
          .addLine(
            r'Apr 26 20:54:02.025982 novio (R14)(Flutter)[1800] <Notice>: flutter: \M-b\M^U\M^T Query Parameters',
          )
          .toList();

      final entry = parser.flush();
      expect(entry, isNotNull);
      expect(entry!.message, 'flutter: ╔ Query Parameters');
    });

    test('export round-trips parsed iOS log entries', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      parser
          .addLine(
            'Apr 23 17:10:40.588246 novio (R14)(Flutter)[5727] <Notice>: flutter: ╟ server: [None]',
          )
          .toList();

      final entry = parser.flush();
      expect(entry, isNotNull);

      final restored = LogEntry.fromExportedMap(entry!.toExportMap());
      expect(restored, isNotNull);
      expect(restored!.timestamp, entry.timestamp);
      expect(restored.level, entry.level);
      expect(restored.tag, entry.tag);
      expect(restored.packageName, entry.packageName);
      expect(restored.processName, entry.processName);
      expect(restored.message, entry.message);
    });

    test('preserves unknown iOS raw level values', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));

      parser
          .addLine(
            'Apr 23 17:10:40.588246 novio[5727] <Panic>: flutter: something unexpected happened',
          )
          .toList();

      final entry = parser.flush();
      expect(entry, isNotNull);
      expect(entry!.level, 'panic');
    });
  });
}
