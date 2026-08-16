import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import 'data/utility_catalog.dart';
import 'data/utility_command.dart';

/// Per-device Utilities feature: exposes the [utilityCatalog] narrowed to what
/// the bound device's platform supports, runs one command at a time, and keeps
/// the latest result for the output panel.
///
/// The controller knows nothing about individual commands — a command carries
/// its own parameters, confirmation text and per-platform builder — so growing
/// the catalog never touches this class.
class UtilitiesController extends FeatureController {
  UtilitiesController(super.session);

  /// How long a single utility may run before it is killed. `dumpsys package`
  /// on a big app and `monkey` runs are the slow end of the range.
  static const Duration commandTimeout = Duration(seconds: 45);

  double paneWidth = 420;

  String _searchText = '';
  String? _runningCommandId;
  UtilityRunResult? _lastResult;
  bool _disposed = false;

  String get searchText => _searchText;
  String? get runningCommandId => _runningCommandId;
  bool get isRunning => _runningCommandId != null;
  UtilityRunResult? get lastResult => _lastResult;

  /// The catalog narrowed to this device's platform, then to [searchText].
  /// Groups left with no matching command are dropped.
  List<UtilityGroup> get groups {
    final query = _searchText.trim().toLowerCase();
    final result = <UtilityGroup>[];
    for (final group in utilityCatalog) {
      final commands = group.commands
          .where((command) => command.supports(device))
          .where((command) => _matches(command, group, query))
          .toList();
      if (commands.isNotEmpty) result.add(group.withCommands(commands));
    }
    return result;
  }

  /// Whether this device's platform has any utility at all — false only for
  /// the synthetic imported-logs workspace and other device-less sessions.
  bool get hasAnyUtility => utilityCatalog.any(
    (group) => group.commands.any((command) => command.supports(device)),
  );

  bool _matches(UtilityCommand command, UtilityGroup group, String query) {
    if (query.isEmpty) return true;
    if (command.label.toLowerCase().contains(query)) return true;
    if (command.description.toLowerCase().contains(query)) return true;
    if (group.title.toLowerCase().contains(query)) return true;
    final preview = command.previewFor(device)?.toLowerCase();
    return preview != null && preview.contains(query);
  }

  void setSearchText(String value) {
    if (_searchText == value) return;
    _searchText = value;
    _notify();
  }

  void setPaneWidth(double width) {
    final clamped = width.clamp(320.0, 900.0);
    if (clamped == paneWidth) return;
    paneWidth = clamped;
    _notify();
  }

  void clearResult() {
    if (_lastResult == null) return;
    _lastResult = null;
    _notify();
  }

  /// Runs [command] with the collected [values]. Returns the result (also
  /// stored as [lastResult]), or null when the run was rejected — another
  /// command is already in flight, the device dropped, or the command turned
  /// out not to be supported here.
  Future<UtilityRunResult?> run(
    UtilityCommand command, {
    Map<String, String> values = const {},
  }) async {
    if (_disposed || isRunning) return null;

    final invocation = command.build(device, UtilityArgs(values));
    if (invocation == null) return null;

    if (!isConnected) {
      return _finish(
        command,
        UtilityRunResult(
          commandId: command.id,
          label: command.label,
          commandLine: invocation.displayCommand,
          exitCode: -1,
          output: '',
          finishedAt: DateTime.now(),
          failure:
              '${device.displayName} is disconnected. Reconnect it and try '
              'again.',
        ),
      );
    }

    _runningCommandId = command.id;
    _notify();

    try {
      final result = await service.runUtility(
        invocation,
        timeout: commandTimeout,
      );
      return _finish(
        command,
        UtilityRunResult(
          commandId: command.id,
          label: command.label,
          commandLine: invocation.displayCommand,
          exitCode: result.exitCode,
          output: result.combinedOutput,
          finishedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      return _finish(
        command,
        UtilityRunResult(
          commandId: command.id,
          label: command.label,
          commandLine: invocation.displayCommand,
          exitCode: -1,
          output: '',
          finishedAt: DateTime.now(),
          failure: describeError(error),
        ),
      );
    } finally {
      _runningCommandId = null;
      _notify();
    }
  }

  /// Stores [result] for the output panel and returns it. A side-effect-only
  /// command that succeeded has nothing worth panelling — the view reports it
  /// with a snackbar instead — so it clears the panel rather than filling it
  /// with "(no output)".
  UtilityRunResult? _finish(UtilityCommand command, UtilityRunResult result) {
    if (_disposed) return null;
    _lastResult = command.expectsOutput || !result.isSuccess ? result : null;
    _notify();
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
