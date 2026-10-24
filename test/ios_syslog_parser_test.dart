import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/services/log_formats/log_formats.dart';
import 'package:eagly/features/logs/services/log_parsers/ios_syslog_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _format = AndroidLogcatFormat();

void main() {
  group('IosSyslogParser', () {
    test('reads the thread ID after the pid, and 0 where there is none', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 10, 25));
      final logs = [
        ...parser.addLine(
          'Oct 25 14:02:11.004211 Runner(CoreFoundation)[812:1036839] <Notice>: from a thread',
        ),
        ...parser.addLine(
          'Oct 25 14:02:11.004300 Runner(CoreFoundation)[812] <Notice>: from idevicesyslog',
        ),
        ?parser.flush(),
      ];

      expect(logs, hasLength(2));
      expect(logs.first.pid, '812');
      expect(logs.first.tid, '1036839');
      expect(logs.first.processName, 'Runner(CoreFoundation)');
      expect(logs.first.message, 'from a thread');
      expect(logs.last.pid, '812');
      expect(logs.last.tid, '0');
    });

    test(
      'a continuation flushed apart from its header keeps its thread ID',
      () {
        final parser = IosSyslogParser(now: () => DateTime(2026, 10, 25));
        parser.addLine(
          'Oct 25 14:02:11.004211 Runner[812:1036839] <Error>: first line',
        );
        parser.flush();
        parser.addLine('second line');

        final resumed = parser.flush();
        expect(resumed?.tid, '1036839');
        expect(resumed?.message, 'second line');
      },
    );

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
      expect(logs.first.id, greaterThanOrEqualTo(0));
      expect(logs.last.id, logs.first.id + 1);
      expect(logs.first.id, isNot(logs.last.id));
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
          'Apr 23 17:10:40.588177 Runner (R14)(Flutter)[5727] <Notice>: flutter: ╟ x-xss-protection: [1; mode=block]',
        ),
      );
      final trailingEntry = parser.flush();
      if (trailingEntry != null) {
        logs.add(trailingEntry);
      }

      expect(logs, hasLength(1));
      expect(logs.single.timestamp, '2026-04-23 17:10:40.588');
      expect(logs.single.level, 'default');
      // Tag is the last bracketed value (the iOS subsystem/category); the bare
      // process name and the full label are kept separately.
      expect(logs.single.tag, 'Flutter');
      expect(logs.single.packageName, 'Runner');
      expect(logs.single.processName, 'Runner (R14)(Flutter)');
      expect(
        logs.single.message,
        'flutter: ╟ x-xss-protection: [1; mode=block]',
      );
    });

    test('extracts process name and category from labels with parentheses', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 6, 9));
      final logs = <LogEntry>[];
      final lines = <String>[
        'Jun  9 15:06:06.533981 Runner (R14)(CoreFoundation)[2768] <Debug>: looked up value',
        'Jun  9 15:06:06.534469 runningboardd(RunningBoard)[33] <Info>: PERF: Received request',
      ];
      for (final line in lines) {
        logs.addAll(parser.addLine(line));
      }
      final trailing = parser.flush();
      if (trailing != null) logs.add(trailing);

      expect(logs, hasLength(2));

      // "Runner (R14)(CoreFoundation)" → process "Runner", category "CoreFoundation".
      expect(logs.first.packageName, 'Runner');
      expect(logs.first.tag, 'CoreFoundation');
      expect(logs.first.processName, 'Runner (R14)(CoreFoundation)');
      // TID is never available in idevicesyslog output; PID is captured.
      expect(logs.first.pid, '2768');
      expect(logs.first.tid, '0');

      // "runningboardd(RunningBoard)" → process "runningboardd", category "RunningBoard".
      expect(logs.last.packageName, 'runningboardd');
      expect(logs.last.tag, 'RunningBoard');
      expect(logs.last.processName, 'runningboardd(RunningBoard)');
    });

    test('decodes cat-v style meta escapes emitted by piped iOS syslog', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 26));

      parser.addLine(
        r'Apr 26 20:54:02.025982 Runner (R14)(Flutter)[1800] <Notice>: flutter: \M-b\M^U\M^T Query Parameters',
      );

      final entry = parser.flush();
      expect(entry, isNotNull);
      expect(entry!.message, 'flutter: ╔ Query Parameters');
    });

    test('export round-trips parsed iOS log entries', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      parser.addLine(
        'Apr 23 17:10:40.588246 Runner (R14)(Flutter)[5727] <Notice>: flutter: ╟ server: [None]',
      );

      final entry = parser.flush();
      expect(entry, isNotNull);

      final exported = _format.export([entry!]).content;
      final restored = _format.parse(exported).logs.firstOrNull;

      expect(exported.contains('"id"'), isFalse);
      expect(restored, isNotNull);
      expect(restored!.id, isNot(entry.id));
      expect(restored.timestamp, entry.timestamp);
      expect(restored.level, entry.level);
      expect(restored.tag, entry.tag);
      expect(restored.packageName, entry.packageName);
      expect(restored.processName, entry.processName);
      expect(restored.message, entry.message);
    });

    test('continuations after a flush start a new entry under its header', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      parser.addLine(
        'Apr 23 17:10:40.588246 Runner (R14)(Flutter)[5727] <Notice>: head',
      );
      final first = parser.flush()!;

      parser.addLine('late one');
      parser.addLine('late two');
      final rest = parser.flush()!;

      expect(first.message, 'head');
      expect(rest.message, 'late one\nlate two');
      expect(
        [rest.timestamp, rest.pid, rest.level, rest.tag, rest.processName],
        [first.timestamp, first.pid, first.level, first.tag, first.processName],
      );
    });

    test('blank continuations after a flush add no empty row', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      parser.addLine('Apr 23 17:10:40.588246 Runner[5727] <Notice>: head');
      parser.flush();

      parser.addLine('');
      parser.addLine('   ');
      expect(parser.flush(), isNull);
    });

    test('ignores continuations before the first header', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));

      expect(parser.addLine('orphan'), isEmpty);
      expect(parser.flush(), isNull);
    });

    test('idevicesyslog status lines end an entry and are dropped', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));
      expect(parser.addLine('[connected:00008140-001564CA3493801C]'), isEmpty);
      parser.addLine('Apr 23 17:10:40.588246 Runner[5727] <Notice>: before');
      parser.addLine('  continued');

      final ended = parser.addLine('[disconnected:00008140-001564CA3493801C]');
      expect(ended.single.message, 'before\n  continued');

      // Neither the status lines nor what follows them join that entry.
      expect(parser.addLine('[connected:00008140-001564CA3493801C]'), isEmpty);
      expect(parser.addLine('orphan'), isEmpty);
      parser.addLine('Apr 23 17:10:41.000000 Runner[5727] <Notice>: after');
      expect(parser.flush()?.message, 'after');
    });

    test('preserves unknown iOS raw level values', () {
      final parser = IosSyslogParser(now: () => DateTime(2026, 4, 23));

      parser.addLine(
        'Apr 23 17:10:40.588246 Runner[5727] <Panic>: flutter: something unexpected happened',
      );

      final entry = parser.flush();
      expect(entry, isNotNull);
      expect(entry!.level, 'panic');
    });
  });
}
