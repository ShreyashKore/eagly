import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_constants.dart';
import '../logs/log_constants.dart';
import '../logs/log_controller.dart';
import '../../intents/intents.dart';
import '../../services/eagly_info_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_manager.dart';
import '../../utils/log_feedback.dart';
import '../settings/settings_screen.dart';
import '../wireless_connection/wireless_connection_dialog.dart';
import 'app_header.dart';
import 'device_screen.dart';
import 'home_page_support.dart';
import 'home_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceSessionManager _manager = DeviceSessionManager();
  final ValueNotifier<int> _appMemoryBytes = ValueNotifier<int>(0);
  Timer? _memoryRefreshTimer;

  bool get _supportsDesktopMenuBar => Platform.isMacOS;

  LogController? get _activeLog =>
      _manager.selected?.logSessionManager.selectedTab;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerChanged);
    _refreshAppMemory();
    _memoryRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAppMemory();
    });
  }

  @override
  void dispose() {
    _memoryRefreshTimer?.cancel();
    _appMemoryBytes.dispose();
    _manager.removeListener(_onManagerChanged);
    _manager.dispose();
    super.dispose();
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
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

  void _runOnActiveLog(void Function(LogController log) action) {
    final log = _activeLog;
    if (log == null) return;
    action(log);
  }

  List<PlatformMenuItem> _logLevelFilterMenuItems() {
    final isIos = _activeLog?.isIosLogContext ?? false;
    return buildLogLevelMenuItems(
      isIos: isIos,
      onSelected: (level) =>
          _runOnActiveLog((log) => log.setSelectedLogLevel(level)),
    );
  }

  List<PlatformMenuItem> _buildDesktopMenus() {
    final canInstall = _manager.selected?.isConnected == true;

    return [
      // ── File ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Install App on Selected Device…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyI,
                  meta: true,
                  shift: true,
                ),
                onSelected: canInstall
                    ? () => unawaited(_handleInstallApp())
                    : null,
              ),
              PlatformMenuItem(
                label: 'Export Logs…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                  shift: true,
                ),
                onSelected: _activeLog == null
                    ? null
                    : () => unawaited(_handleExportLogs()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Settings…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: _openSettings,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Quit ${AppConstants.appName}',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyQ,
                  meta: true,
                ),
                onSelected: () => SystemNavigator.pop(),
              ),
            ],
          ),
        ],
      ),

      // ── Logs ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Logs',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Reload Devices',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyR,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => unawaited(_manager.refreshDevices()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Start / Restart Logcat',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyR,
                  meta: true,
                ),
                onSelected: () => _runOnActiveLog((log) => log.startLogcat()),
              ),
              PlatformMenuItem(
                label: 'Pause / Resume Logcat',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.space,
                  meta: true,
                ),
                onSelected: () =>
                    _runOnActiveLog((log) => log.togglePauseResume()),
              ),
              PlatformMenuItem(
                label: 'Clear Logs',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyK,
                  meta: true,
                ),
                onSelected: () => _runOnActiveLog((log) => log.clearLogs()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Scroll to End',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.end,
                  meta: true,
                ),
                onSelected: () => _runOnActiveLog((log) => log.scrollToEnd()),
              ),
            ],
          ),
        ],
      ),

      // ── Search ────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Search',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Find…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  meta: true,
                ),
                onSelected: () =>
                    _runOnActiveLog((log) => log.activateSearchFromSelection()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Previous Match',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyG,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => _runOnActiveLog((log) => log.onSearchPrev()),
              ),
              PlatformMenuItem(
                label: 'Next Match',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyG,
                  meta: true,
                ),
                onSelected: () => _runOnActiveLog((log) => log.onSearchNext()),
              ),
            ],
          ),
        ],
      ),

      // ── Filter ────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Filter',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Focus Filter Input',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyL,
                  meta: true,
                ),
                onSelected: () =>
                    _runOnActiveLog((log) => log.focusFilterInputs()),
              ),
              PlatformMenuItem(
                label: 'Clear Filter',
                onSelected: () => _runOnActiveLog((log) => log.clearFilter()),
              ),
            ],
          ),
          PlatformMenuItemGroup(members: _logLevelFilterMenuItems()),
        ],
      ),

      // ── View ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Toggle Wrap Text',
                onSelected: () =>
                    _runOnActiveLog((log) => log.toggleWrapText()),
              ),
              PlatformMenuItem(
                label: 'Toggle Auto-scroll',
                onSelected: () =>
                    _runOnActiveLog((log) => log.toggleAutoScroll()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Increase Font Size',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.equal,
                  meta: true,
                ),
                onSelected: () => _changeLogFontSize(1),
              ),
              PlatformMenuItem(
                label: 'Decrease Font Size',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.minus,
                  meta: true,
                ),
                onSelected: () => _changeLogFontSize(-1),
              ),
            ],
          ),
        ],
      ),

      // ── Help ──────────────────────────────────────────────────────────────
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About ${AppConstants.appName}',
                onSelected: _showAboutApp,
              ),
            ],
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);

    final content = Shortcuts(
      shortcuts: homePageShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateSearchIntent: CallbackAction<ActivateSearchIntent>(
            onInvoke: (_) {
              _activeLog?.activateSearchFromSelection();
              return null;
            },
          ),
          IncreaseFontIntent: CallbackAction<IncreaseFontIntent>(
            onInvoke: (_) {
              _changeLogFontSize(1);
              return null;
            },
          ),
          DecreaseFontIntent: CallbackAction<DecreaseFontIntent>(
            onInvoke: (_) {
              _changeLogFontSize(-1);
              return null;
            },
          ),
        },
        child: Focus(
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
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (_supportsDesktopMenuBar) {
      return PlatformMenuBar(menus: _buildDesktopMenus(), child: content);
    }

    return content;
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
