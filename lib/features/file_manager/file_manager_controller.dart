import 'dart:async';

import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import 'data/device_file_entry.dart';
import 'services/device_file_system.dart';
import 'services/file_transfer_picker.dart';

enum FileManagerViewMode { list, grid }

enum FileLoadState { idle, loading, ready, error }

enum FileSortField { name, size, modified, type }

/// Per-device file-manager feature. Owns the navigation state (current path +
/// back history), the current directory listing, view/sort preferences, and
/// the busy state for transfers. The browsable file system itself is supplied
/// by [DeviceFileSystem], chosen from the device platform — so this controller
/// is platform-agnostic.
///
/// Pane *visibility* lives on the owning [DeviceSessionController]; this
/// controller only manages the feature's own state.
class FileManagerController extends FeatureController {
  FileManagerController(super.session);

  late final DeviceFileSystem fileSystem = DeviceFileSystem.forDevice(device);

  FileLoadState loadState = FileLoadState.idle;
  String? error;
  List<DeviceFileEntry> _entries = const [];
  DeviceFileEntry? selectedEntry;

  late String currentPath = fileSystem.initialPath;
  final List<String> _backStack = [];

  FileManagerViewMode viewMode = FileManagerViewMode.list;
  FileSortField sortField = FileSortField.name;
  bool sortAscending = true;

  bool _busy = false;
  String? busyLabel;

  double paneWidth = 600;

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

  /// The current directory's entries, directories-first then by the active
  /// sort field/order.
  List<DeviceFileEntry> get entries {
    final sorted = [..._entries];
    sorted.sort(_compareEntries);
    return sorted;
  }

  int get entryCount => _entries.length;
  int get directoryCount => _entries.where((e) => e.isDirectory).length;
  int get fileCount => _entries.where((e) => e.isFile).length;

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
    if (recordHistory && path != currentPath) {
      _backStack.add(currentPath);
    }
    await _load(path);
  }

  Future<void> navigateUp() async {
    if (!canGoUp) return;
    await navigateTo(posixParent(currentPath));
  }

  Future<void> navigateBack() async {
    if (_backStack.isEmpty) return;
    final previous = _backStack.removeLast();
    await _load(previous);
  }

  /// Jumps to an ancestor selected from the breadcrumb bar.
  Future<void> navigateToBreadcrumb(String path) async {
    if (path == currentPath) return;
    await navigateTo(path);
  }

  Future<void> _load(String path) async {
    if (_disposed) return;
    if (!isConnected) {
      loadState = FileLoadState.error;
      error = 'The device is disconnected. Reconnect it to browse files.';
      _notify();
      return;
    }

    final token = ++_loadToken;
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

  void setViewMode(FileManagerViewMode mode) {
    if (viewMode == mode) return;
    viewMode = mode;
    _notify();
  }

  void toggleViewMode() {
    setViewMode(
      viewMode == FileManagerViewMode.list
          ? FileManagerViewMode.grid
          : FileManagerViewMode.list,
    );
  }

  /// Sets the sort field; selecting the active field flips the direction.
  void setSort(FileSortField field) {
    if (sortField == field) {
      sortAscending = !sortAscending;
    } else {
      sortField = field;
      sortAscending = true;
    }
    _notify();
  }

  void setPaneWidth(double width) {
    final clamped = width.clamp(380.0, 960.0);
    if (clamped == paneWidth) return;
    paneWidth = clamped;
    _notify();
  }

  // ── Transfers / mutations ─────────────────────────────────────────────────

  /// Picks one or more local files and uploads them into the current directory.
  /// Returns a status message to show, or `null` when cancelled / busy.
  Future<String?> uploadFiles() async {
    if (_busy || !_ensureConnected()) return error;
    final paths = await FileTransferPicker.pickFilesToUpload(device.displayName);
    if (_disposed || paths.isEmpty) return null;

    return _runTransfer(
      label: paths.length == 1
          ? 'Uploading ${extractFileName(paths.single)}…'
          : 'Uploading ${paths.length} items…',
      action: () async {
        for (final path in paths) {
          await fileSystem.upload(localPath: path, deviceDirectory: currentPath);
        }
        await _load(currentPath);
        return paths.length == 1
            ? 'Uploaded ${extractFileName(paths.single)}.'
            : 'Uploaded ${paths.length} items.';
      },
    );
  }

  /// Downloads [entry] to a chosen local folder. Returns a status message, or
  /// `null` when cancelled / busy.
  Future<String?> downloadEntry(DeviceFileEntry entry) async {
    if (_busy || !_ensureConnected()) return error;
    final directory = await FileTransferPicker.pickDownloadDirectory(entry.name);
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
        await fileSystem.createDirectory(parentPath: currentPath, name: trimmed);
        await _load(currentPath);
        return 'Created folder "$trimmed".';
      },
    );
  }

  Future<String?> renameEntry(DeviceFileEntry entry, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == entry.name || _busy || !_ensureConnected()) {
      return null;
    }

    return _runTransfer(
      label: 'Renaming ${entry.name}…',
      action: () async {
        await fileSystem.rename(entry: entry, newName: trimmed);
        await _load(currentPath);
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
    _notify();
    try {
      final message = await action();
      return _disposed ? null : message;
    } on DeviceFileException catch (err) {
      return err.message;
    } catch (err) {
      return describeError(err);
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

  int _compareEntries(DeviceFileEntry a, DeviceFileEntry b) {
    // Directories always sort before files regardless of the active field.
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;

    final direction = sortAscending ? 1 : -1;
    final result = switch (sortField) {
      FileSortField.name =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      FileSortField.size => (a.sizeBytes ?? 0).compareTo(b.sizeBytes ?? 0),
      FileSortField.modified => (a.modified ?? DateTime(0)).compareTo(
        b.modified ?? DateTime(0),
      ),
      FileSortField.type => a.typeLabel.compareTo(b.typeLabel),
    };
    // Fall back to name for a stable order when the primary key ties.
    if (result == 0 && sortField != FileSortField.name) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return result * direction;
  }

  @override
  void onDeviceDisconnected() {
    error = 'The device disconnected.';
    _notify();
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
