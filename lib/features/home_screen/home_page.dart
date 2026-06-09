import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';
import '../logs/log_controller.dart';
import '../../app_menu/intents.dart';
import '../../services/eagly_info_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_manager.dart';
import '../../utils/log_feedback.dart';
import '../settings/settings_screen.dart';
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

  void _showSnackBar(String message, {double? width}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message), width: width));
  }

  void _changeLogFontSize(double delta) {
    final current = PreferencesService.logFontSize;
    PreferencesService.logFontSize = current + delta;
    final applied = PreferencesService.logFontSize;
    _showSnackBar(
      'Font size: ${applied.toStringAsFixed(0)}',
      width: AppConstants.fontSizeSnackBarWidth,
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
      QuitAppIntent: on<QuitAppIntent>((_) => SystemNavigator.pop()),
      ReloadDevicesIntent: on<ReloadDevicesIntent>(
        (_) => _menuController.reloadDevices(),
      ),
      InstallAppIntent: on<InstallAppIntent>(
        (_) => unawaited(_handleInstallApp()),
      ),
      ExportLogsIntent: on<ExportLogsIntent>(
        (_) => unawaited(_handleExportLogs()),
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
      IncreaseFontIntent: on<IncreaseFontIntent>((_) => _changeLogFontSize(1)),
      DecreaseFontIntent: on<DecreaseFontIntent>((_) => _changeLogFontSize(-1)),
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
      );
    }
    return DeviceScreen(
      session: session,
      appMemoryBytesListenable: _appMemoryBytes,
    );
  }
}
