import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../data/device.dart';
import '../../services/app_breadcrumbs.dart';
import '../../services/preferences_service.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import 'data/device_file_entry.dart';
import 'data/file_view_options.dart';
import 'services/device_file_system.dart';
import 'services/file_transfer_picker.dart';

/// Outcome of copying externally-dropped files onto the device. [copied] holds
/// the file names that landed in [directory]; [errors] are human-readable
/// per-file failures.
class const FileDropCopyResult({
  required final String directory,
  final List<String> copied = const [],
  final List<String> errors = const [],
});

enum FileLoadState { idle, loading, ready, error }

/// Per-device file-manager feature. Owns the navigation state (current path +
/// back history), the current directory listing, how it is shown (filter,
/// sort, grouping, hidden files — all applied here, on the listing both
/// platforms produce), and the busy state for transfers. The browsable file system itself is supplied
/// by [DeviceFileSystem], chosen from the device platform — so this controller
/// is platform-agnostic.
///
/// Pane *visibility* lives on the owning [DeviceSessionController]; this
/// controller only manages the feature's own state.
class FileManagerController(super.session) extends FeatureController {
  /// Replaces [DeviceFileSystem.forDevice] so tests can copy without a device.
  @visibleForTesting
  static DeviceFileSystem Function(Device device)? fileSystemFactory;

  /// Today, for the date-modified groups; fixed by tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  late final DeviceFileSystem fileSystem =
      fileSystemFactory?.call(device) ?? DeviceFileSystem.forDevice(device);

  FileLoadState loadState = FileLoadState.idle;
  String? error;
  List<DeviceFileEntry> _entries = const [];
  DeviceFileEntry? selectedEntry;

  late String currentPath = fileSystem.initialPath;
  final List<String> _backStack = [];

  // View preferences are shared by every device's pane and remembered;
  // the filter and collapsed groups are this pane's alone.
  FileManagerViewMode viewMode = PreferencesService.filesViewMode;
  FileSortField sortField = PreferencesService.filesSortField;
  bool sortAscending = PreferencesService.filesSortAscending;
  FileGrouping grouping = PreferencesService.filesGrouping;
  bool foldersFirst = PreferencesService.filesFoldersFirst;
  bool showHidden = PreferencesService.filesShowHidden;

  /// Narrows the listing to names containing it (case-insensitive), or
  /// matching it as a glob when it has `*` or `?`. Cleared on leaving the
  /// folder, as Finder and Explorer do.
  String filterText = '';
  final Set<String> _collapsedGroups = {};

  // Derived from the listing and the options above; dropped on every change.
  List<DeviceFileEntry>? _visible;
  List<FileGroup>? _groups;

  bool _busy = false;
  String? busyLabel;

  bool _disposed = false;
  bool _loadedOnce = false;
  int _loadToken = 0;

  // ── Derived getters ───────────────────────────────────────────────────────

  bool get isLoading => loadState == FileLoadState.loading;
  bool get isBusy => _busy;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoUp => currentPath != fileSystem.rootPath;
  bool get supportsCreateDirectory => fileSystem.supportsCreateDirectory;
  bool get supportsDelete => fileSystem.supportsDelete;
  bool get supportsRename => fileSystem.supportsRename;
  String get storageLabel => fileSystem.storageLabel;

  /// The entries shown — hidden files and the filter applied — in display
  /// order: sorted, then (when grouped) group by group.
  List<DeviceFileEntry> get entries =>
      _visible ??= [for (final group in groups) ...group.entries];

  /// [entries] split into [grouping]'s sections; a single unlabelled group
  /// when ungrouped.
  List<FileGroup> get groups =>
      _groups ??= groupFileEntries(_sortedVisible(), grouping, now: clock());

  bool isGroupCollapsed(FileGroup group) =>
      _collapsedGroups.contains(group.key);

  /// The entries a keyboard can reach: [entries] minus collapsed groups.
  List<DeviceFileEntry> get reachableEntries => [
    for (final group in groups)
      if (!isGroupCollapsed(group)) ...group.entries,
  ];

  /// Everything listed in the folder, before hiding or filtering.
  int get entryCount => _entries.length;
  int get visibleCount => entries.length;
  int get directoryCount => _entries.where((e) => e.isDirectory).length;
  int get fileCount => _entries.where((e) => e.isFile).length;

  /// Dotfiles left out while [showHidden] is off.
  int get hiddenCount =>
      showHidden ? 0 : _entries.where((e) => _isHidden(e)).length;
  bool get isFiltered => filterText.trim().isNotEmpty;

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Loads the initial directory the first time the pane is opened. Idempotent.
  Future<void> ensureLoaded() async {
    if (_loadedOnce) return;
    _loadedOnce = true;
    await _load(currentPath);
  }

  Future<void> refresh() => _load(currentPath);

  /// Navigates into [entry] when it is a directory (or symlink), otherwise
  /// selects it.
  Future<void> open(DeviceFileEntry entry) async {
    if (entry.isNavigable) {
      await navigateTo(entry.path);
    } else {
      selectEntry(entry);
    }
  }

  Future<void> navigateTo(String path, {bool recordHistory = true}) async {
    if (path != currentPath) {
      AppBreadcrumbs.navigation(
        from: currentPath,
        to: path,
        category: 'files.navigate',
      );
    }
    if (recordHistory && path != currentPath) {
      _backStack.add(currentPath);
    }
    await _load(path);
  }

  Future<void> navigateUp() async {
    if (!canGoUp) return;
    await navigateTo(posixParent(currentPath));
  }

  /// Opens the selected entry: a folder is entered, a file left selected.
  Future<void> openSelected() async {
    final entry = selectedEntry;
    if (entry != null && entry.isNavigable) await open(entry);
  }

  Future<void> navigateBack() async {
    if (_backStack.isEmpty) return;
    final previous = _backStack.removeLast();
    AppBreadcrumbs.navigation(
      from: currentPath,
      to: previous,
      category: 'files.navigate',
    );
    await _load(previous);
  }

  /// Jumps to an ancestor selected from the breadcrumb bar.
  Future<void> navigateToBreadcrumb(String path) async {
    if (path == currentPath) return;
    await navigateTo(path);
  }

  /// Lists [path]. [select] names the entry to select once it is listed
  /// (one just created or renamed).
  Future<void> _load(String path, {String? select}) async {
    if (_disposed) return;
    if (!isConnected) {
      loadState = FileLoadState.error;
      error = 'The device is disconnected. Reconnect it to browse files.';
      _notify();
      return;
    }

    final token = ++_loadToken;
    // Coming back out of a folder selects it, so the place you were stays
    // marked; a refresh keeps the selection.
    final previousPath = currentPath;
    final keep = select ?? (path == previousPath ? selectedEntry?.path : null);
    if (path != previousPath) filterText = '';
    currentPath = path;
    selectedEntry = null;
    loadState = FileLoadState.loading;
    error = null;
    _notify();

    try {
      final listed = await fileSystem.list(path);
      if (_disposed || token != _loadToken) return;
      _entries = listed;
      loadState = FileLoadState.ready;
      selectedEntry = listed.where((entry) {
        if (keep != null) return entry.path == keep;
        return previousPath == entry.path ||
            previousPath.startsWith('${entry.path}/');
      }).firstOrNull;
      _notify();
    } on DeviceFileException catch (err) {
      if (_disposed || token != _loadToken) return;
      _entries = const [];
      loadState = FileLoadState.error;
      error = err.message;
      _notify();
    } catch (err) {
      if (_disposed || token != _loadToken) return;
      _entries = const [];
      loadState = FileLoadState.error;
      error = describeError(err);
      _notify();
    }
  }

  // ── Selection / view ──────────────────────────────────────────────────────

  void selectEntry(DeviceFileEntry? entry) {
    if (selectedEntry?.path == entry?.path) return;
    selectedEntry = entry;
    _notify();
  }

  /// Moves the selection [delta] places through [reachableEntries] (a grid
  /// passes its column count to move a row), stopping at either end. With
  /// nothing selected it starts from the first entry, or the last going back.
  void moveSelection(int delta) {
    final reachable = reachableEntries;
    if (reachable.isEmpty) return;
    final current = selectedEntry == null
        ? -1
        : reachable.indexWhere((e) => e.path == selectedEntry!.path);
    final next = current < 0
        ? (delta > 0 ? 0 : reachable.length - 1)
        : (current + delta).clamp(0, reachable.length - 1);
    selectEntry(reachable[next]);
  }

  void setFilterText(String value) {
    if (filterText == value) return;
    filterText = value;
    _notify();
  }

  void setViewMode(FileManagerViewMode mode) {
    if (viewMode == mode) return;
    viewMode = mode;
    PreferencesService.filesViewMode = mode;
    _notify();
  }

  void toggleViewMode() {
    setViewMode(
      viewMode == FileManagerViewMode.list
          ? FileManagerViewMode.grid
          : FileManagerViewMode.list,
    );
  }

  /// Sorts by [field] in [ascending] order, or — left out — flips the order
  /// of the active field and starts a new one in its natural direction (a
  /// column header click).
  void setSort(FileSortField field, {bool? ascending}) {
    sortAscending =
        ascending ??
        (sortField == field ? !sortAscending : field.defaultAscending);
    sortField = field;
    PreferencesService.filesSortField = field;
    PreferencesService.filesSortAscending = sortAscending;
    _notify();
  }

  void setGrouping(FileGrouping value) {
    if (grouping == value) return;
    grouping = value;
    PreferencesService.filesGrouping = value;
    _notify();
  }

  void setFoldersFirst(bool value) {
    if (foldersFirst == value) return;
    foldersFirst = value;
    PreferencesService.filesFoldersFirst = value;
    _notify();
  }

  void setShowHidden(bool value) {
    if (showHidden == value) return;
    showHidden = value;
    PreferencesService.filesShowHidden = value;
    if (!value && selectedEntry != null && _isHidden(selectedEntry!)) {
      selectedEntry = null;
    }
    _notify();
  }

  void toggleGroupCollapsed(FileGroup group) {
    if (!_collapsedGroups.remove(group.key)) {
      _collapsedGroups.add(group.key);
      // A selection folded out of sight would be acted on unseen.
      if (group.entries.any((e) => e.path == selectedEntry?.path)) {
        selectedEntry = null;
      }
    }
    _notify();
  }

  // ── Transfers / mutations ─────────────────────────────────────────────────

  /// Picks one or more local files and uploads them into the current directory.
  /// Returns a status message to show, or `null` when cancelled / busy.
  Future<String?> uploadFiles() async {
    if (_busy || !_ensureConnected()) return error;
    final paths = await FileTransferPicker.pickFilesToUpload(
      device.displayName,
    );
    if (_disposed || paths.isEmpty) return null;

    return _runTransfer(
      label: paths.length == 1
          ? 'Uploading ${extractFileName(paths.single)}…'
          : 'Uploading ${paths.length} items…',
      action: () async {
        for (final path in paths) {
          await fileSystem.upload(
            localPath: path,
            deviceDirectory: currentPath,
          );
        }
        await _load(currentPath);
        return paths.length == 1
            ? 'Uploaded ${extractFileName(paths.single)}.'
            : 'Uploaded ${paths.length} items.';
      },
    );
  }

  /// Copies externally-dropped [localPaths] into [directory], or the device's
  /// [DeviceFileSystem.dropTargetDirectory] when none is given (a drop onto
  /// the device screen, so the pane need not be open). The listing is
  /// refreshed only when the drop lands in the currently-shown directory. Each
  /// file is copied independently so one failure doesn't abort the rest.
  Future<FileDropCopyResult> copyExternalFiles(
    List<String> localPaths, {
    String? directory,
  }) async {
    directory ??= fileSystem.dropTargetDirectory;
    final copied = <String>[];
    final errors = <String>[];
    if (localPaths.isEmpty) {
      return FileDropCopyResult(directory: directory);
    }
    if (!isConnected) {
      return FileDropCopyResult(
        directory: directory,
        errors: const [
          'The device is disconnected. Reconnect it to copy files.',
        ],
      );
    }

    _busy = true;
    busyLabel = localPaths.length == 1
        ? 'Copying ${extractFileName(localPaths.single)}…'
        : 'Copying ${localPaths.length} items…';
    error = null;
    _notify();
    try {
      for (final path in localPaths) {
        try {
          await fileSystem.upload(localPath: path, deviceDirectory: directory);
          copied.add(extractFileName(path));
        } on DeviceFileException catch (err) {
          errors.add(err.message);
        } catch (err) {
          errors.add(describeError(err));
        }
      }
      if (!_disposed && copied.isNotEmpty && currentPath == directory) {
        await _load(currentPath);
      }
    } finally {
      _busy = false;
      busyLabel = null;
      _notify();
    }
    AppBreadcrumbs.action(
      'Copied ${copied.length} dropped file(s) to $directory',
      category: 'files.transfer',
      level: errors.isEmpty ? SentryLevel.info : SentryLevel.warning,
      data: {'copied': copied.length, 'errors': errors.length},
    );
    return FileDropCopyResult(
      directory: directory,
      copied: copied,
      errors: errors,
    );
  }

  /// Downloads [entry] to a chosen local folder. Returns a status message, or
  /// `null` when cancelled / busy.
  Future<String?> downloadEntry(DeviceFileEntry entry) async {
    if (_busy || !_ensureConnected()) return error;
    final directory = await FileTransferPicker.pickDownloadDirectory(
      entry.name,
    );
    if (_disposed || directory == null) return null;

    return _runTransfer(
      label: 'Downloading ${entry.name}…',
      action: () async {
        final saved = await fileSystem.download(
          entry: entry,
          localDirectory: directory,
        );
        return 'Saved ${entry.name} to $saved.';
      },
    );
  }

  Future<String?> createDirectory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _busy || !_ensureConnected()) return null;

    return _runTransfer(
      label: 'Creating "$trimmed"…',
      action: () async {
        await fileSystem.createDirectory(
          parentPath: currentPath,
          name: trimmed,
        );
        await _load(currentPath, select: posixJoin(currentPath, trimmed));
        return 'Created folder "$trimmed".';
      },
    );
  }

  Future<String?> renameEntry(DeviceFileEntry entry, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty ||
        trimmed == entry.name ||
        _busy ||
        !_ensureConnected()) {
      return null;
    }

    return _runTransfer(
      label: 'Renaming ${entry.name}…',
      action: () async {
        await fileSystem.rename(entry: entry, newName: trimmed);
        await _load(currentPath, select: posixJoin(currentPath, trimmed));
        return 'Renamed to "$trimmed".';
      },
    );
  }

  Future<String?> deleteEntry(DeviceFileEntry entry) async {
    if (_busy || !_ensureConnected()) return error;

    return _runTransfer(
      label: 'Deleting ${entry.name}…',
      action: () async {
        await fileSystem.delete(entry);
        await _load(currentPath);
        return 'Deleted ${entry.name}.';
      },
    );
  }

  /// Runs a mutating/transfer [action], managing busy state and turning
  /// [DeviceFileException]s into user-facing messages.
  Future<String?> _runTransfer({
    required String label,
    required Future<String> Function() action,
  }) async {
    _busy = true;
    busyLabel = label;
    error = null;
    AppBreadcrumbs.action(
      label,
      category: 'files.transfer',
      data: {'deviceId': device.id, 'path': currentPath},
    );
    _notify();
    try {
      final message = await action();
      return _disposed ? null : message;
    } on DeviceFileException catch (err) {
      AppBreadcrumbs.action(
        'File op failed: $label',
        category: 'files.transfer',
        level: SentryLevel.error,
        data: {'error': err.message},
      );
      return err.message;
    } catch (err) {
      final message = describeError(err);
      AppBreadcrumbs.action(
        'File op failed: $label',
        category: 'files.transfer',
        level: SentryLevel.error,
        data: {'error': message},
      );
      return message;
    } finally {
      _busy = false;
      busyLabel = null;
      _notify();
    }
  }

  bool _ensureConnected() {
    if (isConnected) return true;
    error = 'The device is disconnected. Reconnect it to manage files.';
    _notify();
    return false;
  }

  List<DeviceFileEntry> _sortedVisible() {
    final matches = _filterMatcher();
    return [
      for (final entry in _entries)
        if ((showHidden || !_isHidden(entry)) && matches(entry.name)) entry,
    ]..sort(_compareEntries);
  }

  static bool _isHidden(DeviceFileEntry entry) => entry.name.startsWith('.');

  /// Substring match, or a whole-name glob when the filter has `*` or `?`
  /// (`*.png`, `IMG_00??.jpg`). Case-insensitive either way.
  bool Function(String name) _filterMatcher() {
    final query = filterText.trim().toLowerCase();
    if (query.isEmpty) return (_) => true;
    if (!query.contains('*') && !query.contains('?')) {
      return (name) => name.toLowerCase().contains(query);
    }
    final glob = query
        .split('')
        .map(
          (char) => switch (char) {
            '*' => '.*',
            '?' => '.',
            _ => RegExp.escape(char),
          },
        );
    final pattern = RegExp('^${glob.join()}\$', caseSensitive: false);
    return pattern.hasMatch;
  }

  int _compareEntries(DeviceFileEntry a, DeviceFileEntry b) {
    // Folder-like entries (directories and symlinks, which navigate like
    // folders) lead regardless of the sort field, unless turned off.
    if (foldersFirst && a.isNavigable != b.isNavigable) {
      return a.isNavigable ? -1 : 1;
    }

    final result = switch (sortField) {
      FileSortField.name => 0,
      FileSortField.kind => FileKind.of(
        a,
      ).index.compareTo(FileKind.of(b).index),
      FileSortField.size => (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0),
      FileSortField.modified => (a.modified ?? DateTime(0)).compareTo(
        b.modified ?? DateTime(0),
      ),
    };
    // Ties — and the whole of a Name sort — fall to the name, which follows
    // the chosen direction too.
    final ordered = result != 0 ? result : compareFileNames(a.name, b.name);
    return sortAscending ? ordered : -ordered;
  }

  @override
  void onDeviceDisconnected() {
    error = 'The device disconnected.';
    _notify();
  }

  void _notify() {
    _visible = null;
    _groups = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
