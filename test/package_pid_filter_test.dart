import 'package:eagly/features/logs/data/models/log_entry.dart';
import 'package:eagly/features/logs/data/models/log_filters.dart';
import 'package:eagly/features/logs/data/models/log_level.dart';
import 'package:eagly/features/logs/services/filter_utils.dart';
import 'package:eagly/features/logs/services/pid_package_index.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _log({
  String pid = '100',
  String message = 'message',
  String? packageName,
  String? processName,
}) => LogEntry(
  timestamp: '',
  pid: pid,
  tid: '200',
  level: 'I',
  tag: 'Tag',
  message: message,
  packageName: packageName,
  processName: processName,
);

LogFilters _parse(String text) => LogFilters.parse(
  text,
  fallbackLevel: LogLevel.verbose,
  isIosLogContext: false,
);

bool _matches(
  LogFilters filters,
  LogEntry log, {
  PackageForPid? packageForPid,
}) => matchesLogFilters(
  log,
  filters,
  LogLevel.verbose,
  packageForPid: packageForPid,
);

void main() {
  group('package filter also matches on pid', () {
    test('matches an entry whose package resolved', () {
      expect(
        _matches(_parse('package:com.foo'), _log(packageName: 'com.foo')),
        isTrue,
      );
    });

    test('matches an unresolved entry by the pid the index remembers', () {
      final index = PidPackageIndex()..record(_log(packageName: 'com.foo'));
      final unresolved = _log(pid: '100');

      expect(_matches(_parse('package:com.foo'), unresolved), isFalse);
      expect(
        _matches(
          _parse('package:com.foo'),
          unresolved,
          packageForPid: index.packageForPid,
        ),
        isTrue,
      );
    });

    test('does not match an unresolved entry from a different pid', () {
      final index = PidPackageIndex()..record(_log(packageName: 'com.foo'));
      expect(
        _matches(
          _parse('package:com.foo'),
          _log(pid: '999'),
          packageForPid: index.packageForPid,
        ),
        isFalse,
      );
    });

    test('a pid typed into the package field matches that pid', () {
      expect(_matches(_parse('package=:100'), _log(pid: '100')), isTrue);
      expect(_matches(_parse('package=:100'), _log(pid: '101')), isFalse);
    });

    test('negation excludes both the package and its remembered pid', () {
      final index = PidPackageIndex()..record(_log(packageName: 'com.foo'));
      final filters = _parse('-package:com.foo');

      expect(
        _matches(
          filters,
          _log(packageName: 'com.foo'),
          packageForPid: index.packageForPid,
        ),
        isFalse,
      );
      expect(
        _matches(filters, _log(pid: '100'), packageForPid: index.packageForPid),
        isFalse,
      );
      expect(
        _matches(filters, _log(pid: '999'), packageForPid: index.packageForPid),
        isTrue,
      );
    });
  });

  group('PidPackageIndex', () {
    test('learns from package name and falls back to process name', () {
      final index = PidPackageIndex()
        ..record(_log(pid: '1', packageName: 'com.foo'))
        ..record(_log(pid: '2', processName: 'surfaceflinger'));

      expect(index.packageForPid('1'), 'com.foo');
      expect(index.packageForPid('2'), 'surfaceflinger');
      expect(index.packageForPid('3'), isNull);
    });

    test('falls back to the device map for a pid no entry resolved', () {
      final deviceMap = {'1': 'com.foo', '2': 'com.bar'};
      final index = PidPackageIndex(fallback: (pid) => deviceMap[pid])
        ..record(_log(pid: '2', packageName: 'com.bar.subprocess'));

      expect(index.packageForPid('1'), 'com.foo', reason: 'from the fallback');
      expect(
        index.packageForPid('2'),
        'com.bar.subprocess',
        reason: 'a learned mapping wins over the polled one',
      );
      expect(index.packageForPid('3'), isNull);
    });

    test('the fallback still keeps unresolved entries in a package filter', () {
      final index = PidPackageIndex(fallback: (pid) => 'com.foo');

      expect(
        matchesLogFilters(
          _log(pid: '100'),
          _parse('package:com.foo'),
          LogLevel.verbose,
          packageForPid: index.packageForPid,
        ),
        isTrue,
      );
    });

    test('record reports only newly learned mappings', () {
      final index = PidPackageIndex();

      expect(index.record(_log(pid: '1', packageName: 'com.foo')), 'com.foo');
      expect(
        index.record(_log(pid: '1', packageName: 'com.foo')),
        isNull,
        reason: 'same mapping again',
      );
      expect(index.record(_log(pid: '2')), isNull, reason: 'nothing to learn');
      expect(index.record(_log(pid: '')), isNull, reason: 'no pid');

      index.clear();
      expect(index.packageForPid('1'), isNull);
    });
  });
}
