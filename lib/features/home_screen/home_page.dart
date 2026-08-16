import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../logs/log_controller.dart';
import '../../app_menu/intents.dart';
import '../../command_palette/command_palette_dialog.dart';
import '../../command_palette/command_palette_items.dart';
import '../../services/eagly_info_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_manager.dart';
import '../../utils/log_feedback.dart';
import '../settings/settings_screen.dart';
import '../tips/tips_controller.dart';
import '../wireless_connection/wireless_connection_dialog.dart';
import 'app_header.dart';
import '../../app_menu/app_menu_controller.dart';
import '../../app_menu/app_menu_scope.dart';
import '../../app_menu/shortcuts.dart';
import '../../app_menu/app_platform_menu_bar.dart';
import 'device_screen.dart';
import 'home_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceSessionManager _manager = DeviceSessionManager();
  final TipsController _tipsController = TipsController();
  late final AppMenuController _menuController = AppMenuController(_manager);
  final ValueNotifier<int> _appMemoryBytes = ValueNotifier<int>(0);
  Timer? _memoryRefreshTimer;

  bool get _supportsDesktopMenuBar => Platform.isMacOS;

  LogController? get _activeLog =>
      _manager.selected?.logSessionManager.selectedTab;

  @override
  void initState() {
    super.initState();
    _refreshAppMemory();
    _memoryRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAppMemory();
    });
  }

  @override
  void dispose() {
    _memoryRefreshTimer?.cancel();
    _appMemoryBytes.dispose();
    _menuController.dispose();
    _tipsController.dispose();
    _manager.dispose();
    super.dispose();
  }

  void _refreshAppMemory() {
    final rss = ProcessInfo.currentRss;
    if (_appMemoryBytes.value != rss) {
      _appMemoryBytes.value = rss;
    }
  }

  Future<void> _openSettings() async {
    await showSettingsDialog(context);
    if (!mounted) return;
    setState(() {});
  }

  void _showAboutApp() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: EaglyInfoService.appVersion,
      applicationIcon: Icon(
        Icons.developer_board,
        size: 44,
        color: Theme.of(context).colorScheme.primary,
      ),
      children: const [Text(AppConstants.appDescription)],
    );
  }

  void _showSnackBar(String message, {double? width, Duration? duration}) {
    final messenger = ScaffoldMessenger.of(context);
    // `remove` rather than `hide`: hiding plays the outgoing snack bar's exit
    // animation first, so repeated messages (holding the zoom shortcut) queue
    // up behind it instead of replacing it.
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        width: width,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  void _changeZoomLevel(double delta) {
    final current = PreferencesService.zoomLevel;
    PreferencesService.zoomLevel = current + delta;
    final applied = PreferencesService.zoomLevel;
    _showSnackBar(
      'Zoom: ${(applied * 100).toStringAsFixed(0)}%',
      width: AppConstants.fontSizeSnackBarWidth,
      // Transient feedback for a repeatable shortcut — gone before the next
      // press feels blocked by it.
      duration: const Duration(milliseconds: 900),
    );
  }

  Future<void> _showWirelessDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => WirelessConnectionDialog(
        manager: _manager,
        onShowSnackBar: _showSnackBar,
      ),
    );
  }

  Future<void> _handleInstallApp() async {
    final session = _manager.selected;
    if (session == null) return;
    final result = await session.installAppFromPicker();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatAppInstallMessage(result));
  }

  Future<void> _handleExportLogs() async {
    final log = _activeLog;
    if (log == null) return;
    final result = await log.exportLogs();
    if (!mounted || result.cancelled) return;
    _showSnackBar(formatExportLogsMessage(result));
  }

  /// Opens a log file without a connected device (via picker, or [path] to
  /// re-open a recent file), routing it into the "Imported Logs" workspace tab.
  Future<void> _handleImportLog({String? path}) async {
    final result = await _manager.importLog(path: path);
    if (!mounted || result.cancelled) return;
    if (result.isSuccess) {
      _showSnackBar(
        'Imported ${result.fileName} (${result.logs!.length} entries).',
      );
      return;
    }
    // A recent file that no longer opens (deleted/moved) is dropped silently.
    if (path != null) {
      unawaited(PreferencesService.removeRecentLogFile(path));
    }
    if (result.error != null) _showSnackBar(result.error!);
  }

  Future<void> _openCommandPalette() async {
    await showCommandPalette(
      context: context,
      listenable: Listenable.merge([_manager, _menuController]),
      itemsBuilder: () => buildCommandPaletteItems(
        context: context,
        manager: _manager,
        menuController: _menuController,
        onOpenSettings: () => unawaited(_openSettings()),
        onShowAbout: _showAboutApp,
        onQuit: () => exit(0),
        onInstallApp: () => unawaited(_handleInstallApp()),
        onExportLogs: () => unawaited(_handleExportLogs()),
        onShowWireless: () => unawaited(_showWirelessDialog()),
        onImportLog: () => unawaited(_handleImportLog()),
        onZoomIn: () => _changeZoomLevel(0.05),
        onZoomOut: () => _changeZoomLevel(-0.05),
        onShowSnackBar: _showSnackBar,
      ),
    );
  }

  /// The single place that maps each command [Intent] to its behavior. Both the
  /// macOS menu (via `onSelectedIntent`) and the keyboard [appShortcuts] route
  /// through this map. Log commands delegate to [AppMenuController]; window/UI
  /// commands run here where the [BuildContext] lives.
  Map<Type, Action<Intent>> _buildActions() {
    CallbackAction<T> on<T extends Intent>(void Function(T intent) run) {
      return CallbackAction<T>(
        onInvoke: (intent) {
          run(intent);
          return null;
        },
      );
    }

    return <Type, Action<Intent>>{
      // App / window
      OpenSettingsIntent: on<OpenSettingsIntent>(
        (_) => unawaited(_openSettings()),
      ),
      ShowAboutIntent: on<ShowAboutIntent>((_) => _showAboutApp()),
      QuitAppIntent: on<QuitAppIntent>((_) => exit(0)),
      ReloadDevicesIntent: on<ReloadDevicesIntent>(
        (_) => _menuController.reloadDevices(),
      ),
      InstallAppIntent: on<InstallAppIntent>(
        (_) => unawaited(_handleInstallApp()),
      ),
      ExportLogsIntent: on<ExportLogsIntent>(
        (_) => unawaited(_handleExportLogs()),
      ),
      OpenCommandPaletteIntent: on<OpenCommandPaletteIntent>(
        (_) => unawaited(_openCommandPalette()),
      ),
      // Capture
      StartLogcatIntent: on<StartLogcatIntent>(
        (_) => _menuController.startOrRestartLogcat(),
      ),
      TogglePauseResumeIntent: on<TogglePauseResumeIntent>(
        (_) => _menuController.togglePauseResume(),
      ),
      ClearLogsIntent: on<ClearLogsIntent>((_) => _menuController.clearLogs()),
      ScrollToEndIntent: on<ScrollToEndIntent>(
        (_) => _menuController.scrollToEnd(),
      ),
      // Search
      ActivateSearchIntent: on<ActivateSearchIntent>(
        (_) => _menuController.activateSearch(),
      ),
      NextMatchIntent: on<NextMatchIntent>((_) => _menuController.searchNext()),
      PreviousMatchIntent: on<PreviousMatchIntent>(
        (_) => _menuController.searchPrevious(),
      ),
      // Filter
      FocusFilterIntent: on<FocusFilterIntent>(
        (_) => _menuController.focusFilter(),
      ),
      ClearFilterIntent: on<ClearFilterIntent>(
        (_) => _menuController.clearFilter(),
      ),
      SetLogLevelIntent: on<SetLogLevelIntent>(
        (intent) => _menuController.setLogLevel(intent.level),
      ),
      // View
      ToggleWrapTextIntent: on<ToggleWrapTextIntent>(
        (_) => _menuController.toggleWrapText(),
      ),
      ToggleAutoScrollIntent: on<ToggleAutoScrollIntent>(
        (_) => _menuController.toggleAutoScroll(),
      ),
      IncreaseFontIntent: on<IncreaseFontIntent>((_) => _changeZoomLevel(0.05)),
      DecreaseFontIntent: on<DecreaseFontIntent>(
        (_) => _changeZoomLevel(-0.05),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);

    final appBody = Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: materialTheme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              AppHeader(
                manager: _manager,
                tipsController: _tipsController,
                onOpenSettings: _openSettings,
                onShowWireless: _showWirelessDialog,
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _manager,
                  builder: (context, _) => _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Actions(
      actions: _buildActions(),
      child: Shortcuts(
        shortcuts: appShortcuts,
        child: AppMenuScope(
          controller: _menuController,
          child: _supportsDesktopMenuBar
              ? AppPlatformMenuBar(child: appBody)
              : appBody,
        ),
      ),
    );
  }

  Widget _buildBody() {
    final session = _manager.selected;
    if (session == null) {
      return HomeView(
        manager: _manager,
        onShowWireless: _showWirelessDialog,
        onShowMessage: _showSnackBar,
        onImportLog: () => unawaited(_handleImportLog()),
        onOpenRecent: (path) => unawaited(_handleImportLog(path: path)),
      );
    }
    return DeviceScreen(
      session: session,
      appMemoryBytesListenable: _appMemoryBytes,
      onOpenSettings: _openSettings,
    );
  }
}
