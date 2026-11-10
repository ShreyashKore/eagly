import 'dart:async';
import 'dart:math' as math;

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';
import '../../logs/data/models/log_entry.dart';
import '../../logs/data/models/log_filters.dart';
import '../../logs/data/models/log_level.dart';
import '../../logs/log_controller.dart';
import '../../logs/services/filter_utils.dart';
import '../mcp_tool.dart';
import 'mcp_tool_context.dart';

/// The longest message a log entry carries in a result.
const _maxMessageChars = 4000;

const _filterSyntax =
    'Eagly filter-bar syntax: bare words match any field; key:value terms '
    'for tag: (category: on iOS), message:, package:, pid:, level:, age: '
    '(e.g. age:5m); key~:regex for a regular expression, key=:value for an '
    'exact match, a leading - to exclude. Terms are ANDed. Example: '
    '"tag:OkHttp level:w -message~:^heartbeat".';

/// `query_logs` and `wait_for_log`.
List<McpTool> logTools(McpToolContext context) => [
  McpTool(
    name: 'query_logs',
    title: 'Query device logs',
    description:
        'Reads the device log (adb logcat, or the iPhone syslog) that Eagly '
        'has captured, filtered with Eagly\'s filter syntax. Returns the '
        'newest matching lines, oldest first, unless sinceId pages forward '
        'or beforeId pages back. Each line has an id; pass the returned '
        'cursor.newestId as sinceId later to get only what came after. '
        'Starts capture on a device whose logs Eagly is not reading yet. '
        '$untrustedDataNote',
    inputSchema: objectSchema({
      'device': deviceProperty,
      'filter': stringProperty(_filterSyntax),
      'level': stringProperty(
        'Lowest level to include: verbose, debug, info, warning, error or '
        'fault (or V/D/I/W/E/F). Defaults to warning without a filter, '
        'verbose with one.',
      ),
      'sinceId': integerProperty(
        'Only lines after this id, oldest first.',
        minimum: -1,
      ),
      'beforeId': integerProperty(
        'Only lines before this id (the newest of them).',
        minimum: 0,
      ),
      'limit': integerProperty(
        'Most lines to return.',
        minimum: 1,
        maximum: 2000,
        defaultValue: 200,
      ),
      'includeStatus': booleanProperty(
        'Include Eagly\'s own status lines (capture started, paused, errors).',
        defaultValue: false,
      ),
    }),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final log = _liveLog(session);
      final startedNow = _ensureCapturing(log);
      final filters = _parseFilters(args, log, session);
      final sinceId = args.integer('sinceId', min: -1);
      final beforeId = args.integer('beforeId', min: 0);
      if (sinceId != null && beforeId != null) {
        throw const McpToolError('Pass sinceId or beforeId, not both.');
      }
      final limit = args.integer('limit', min: 1, max: 2000) ?? 200;
      final includeStatus = args.boolean('includeStatus') ?? false;

      final all = log.logs;
      bool matches(LogEntry entry) => entry.type.isSpecial
          ? includeStatus
          : matchesLogFilters(
              entry,
              filters,
              filters.level,
              packageForPid: log.packageForPid,
            );

      final picked = <LogEntry>[];
      var hasMore = false;
      if (sinceId != null) {
        for (final entry in all) {
          if (entry.id <= sinceId || !matches(entry)) continue;
          if (picked.length == limit) {
            hasMore = true;
            break;
          }
          picked.add(entry);
        }
      } else {
        for (var i = all.length - 1; i >= 0; i--) {
          final entry = all[i];
          if (beforeId != null && entry.id >= beforeId) continue;
          if (!matches(entry)) continue;
          if (picked.length == limit) {
            hasMore = true;
            break;
          }
          picked.add(entry);
        }
        picked.setRange(0, picked.length, picked.reversed.toList());
      }

      return McpToolResult.json({
        'device': session.id,
        'entries': [for (final entry in picked) _entryJson(entry)],
        'returned': picked.length,
        'hasMore': hasMore,
        'cursor': {
          'newestId': all.isEmpty ? (sinceId ?? -1) : all.last.id,
          'oldestRetainedId': ?all.firstOrNull?.id,
        },
        'capture': _captureJson(log, startedNow: startedNow),
        if (log.isRetentionFilterActive)
          'note':
              'The user has a log filter active in Eagly, and a full buffer '
              'drops lines outside it first, so older lines may be missing.',
      });
    },
  ),
  McpTool(
    name: 'wait_for_log',
    title: 'Wait for a log line',
    description:
        'Waits until the device logs a line matching the filter, then returns '
        'it with the lines just before it. Checks lines after sinceId first, '
        'so pass the cursor from an earlier query_logs to not miss a line '
        'logged while you were busy (e.g. while installing the app). '
        '$untrustedDataNote',
    inputSchema: objectSchema(
      {
        'device': deviceProperty,
        'filter': stringProperty(_filterSyntax),
        'level': stringProperty(
          'Lowest level to match (verbose, debug, info, warning, error, '
          'fault). Defaults to verbose.',
        ),
        'sinceId': integerProperty(
          'Also match lines already captured after this id. Defaults to now.',
          minimum: -1,
        ),
        'timeoutSeconds': integerProperty(
          'How long to wait.',
          minimum: 1,
          maximum: 120,
          defaultValue: 30,
        ),
      },
      required: ['filter'],
    ),
    handler: (args) async {
      final session = context.resolve(args.string('device'));
      final log = _liveLog(session);
      _ensureCapturing(log);
      args.requiredString('filter');
      final filters = _parseFilters(
        args,
        log,
        session,
        defaultLevel: 'verbose',
      );
      final timeout = Duration(
        seconds: args.integer('timeoutSeconds', min: 1, max: 120) ?? 30,
      );
      final existing = log.logs;
      final sinceId =
          args.integer('sinceId', min: -1) ??
          (existing.isEmpty ? -1 : existing.last.id);

      bool matches(LogEntry entry) =>
          !entry.type.isSpecial &&
          entry.id > sinceId &&
          matchesLogFilters(
            entry,
            filters,
            filters.level,
            packageForPid: log.packageForPid,
          );

      Map<String, Object?> found(LogEntry entry) {
        final all = log.logs;
        final index = all.indexWhere((e) => e.id == entry.id);
        final before = index <= 0
            ? const <LogEntry>[]
            : all.sublist(math.max(0, index - 5), index);
        return {
          'device': session.id,
          'matched': true,
          'entry': _entryJson(entry),
          'before': [
            for (final e in before)
              if (!e.type.isSpecial) _entryJson(e),
          ],
          'cursor': {'newestId': all.isEmpty ? entry.id : all.last.id},
        };
      }

      final already = existing.where(matches).firstOrNull;
      if (already != null) return McpToolResult.json(found(already));

      final completer = Completer<LogEntry?>();
      final subscription = log.appendedLogs.listen((batch) {
        if (completer.isCompleted) return;
        final hit = batch.where(matches).firstOrNull;
        if (hit != null) completer.complete(hit);
      });
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      final hit = await completer.future;
      timer.cancel();
      await subscription.cancel();

      if (hit != null) return McpToolResult.json(found(hit));
      final all = log.logs;
      return McpToolResult.json({
        'device': session.id,
        'matched': false,
        'timedOut': true,
        'cursor': {'newestId': all.isEmpty ? sinceId : all.last.id},
        'capture': _captureJson(log, startedNow: false),
      });
    },
  ),
];

/// The device's first live tab: the one Eagly captures into from the start.
LogController _liveLog(DeviceSessionController session) {
  final tabs = session.logSessionManager.tabs;
  final live = tabs.where((tab) => !tab.isImported).firstOrNull;
  if (live == null) {
    throw McpToolError(
      '${McpToolContext.describeDevice(session)} has no live log.',
    );
  }
  return live;
}

/// Starts capture the way opening the device's tab would, without
/// selecting it. Returns whether it was started now.
bool _ensureCapturing(LogController log) {
  if (log.isActivated || !log.isConnected) return false;
  log.activate();
  return true;
}

LogFilters _parseFilters(
  McpArguments args,
  LogController log,
  DeviceSessionController session, {
  String? defaultLevel,
}) {
  final filterText = args.string('filter') ?? '';
  final levelArg =
      args.string('level') ??
      defaultLevel ??
      (filterText.isEmpty ? 'warning' : 'verbose');
  final level = LogLevel.fromStored(levelArg);
  if (level.isUnknown) {
    throw McpToolError(
      'Unknown level "$levelArg". Use verbose, debug, info, warning, error '
      'or fault.',
    );
  }
  return LogFilters.parse(
    filterText,
    fallbackLevel: level,
    isIosLogContext: session.device is IosDevice,
  );
}

Map<String, Object?> _entryJson(LogEntry entry) {
  final message = entry.message.length > _maxMessageChars
      ? '${entry.message.substring(0, _maxMessageChars)}… '
            '[${entry.message.length - _maxMessageChars} more characters]'
      : entry.message;
  final package = entry.packageName ?? entry.processName;
  return {
    'id': entry.id,
    if (entry.type.isSpecial) 'status': entry.type.name,
    'time': entry.timestamp,
    'level': entry.level,
    'tag': entry.tag,
    if (entry.pid.isNotEmpty) 'pid': entry.pid,
    if (entry.tid.isNotEmpty) 'tid': entry.tid,
    if (package != null && package.isNotEmpty) 'package': package,
    'message': message,
  };
}

Map<String, Object?> _captureJson(
  LogController log, {
  required bool startedNow,
}) => {
  'running': log.isRunning,
  'paused': log.isPaused,
  'interrupted': log.liveLoggingInterrupted,
  'recovering': log.isRecovering,
  if (!log.isConnected) 'note': 'The device is disconnected; these are the lines captured before it dropped.',
  if (startedNow)
    'note':
        'Eagly only now started reading this device\'s log. Android replays '
        'its recent log buffer within a second or two; an iPhone only sends '
        'new lines. Query again shortly, or use wait_for_log.',
};
