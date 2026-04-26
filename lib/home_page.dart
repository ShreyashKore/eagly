import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tabbed_view/tabbed_view.dart';

import 'constants/app_constants.dart';
import 'constants/log_constants.dart';
import 'controllers/log_tab_controller.dart';
import 'home_page_support.dart';
import 'intents/home_page_intents.dart';
import 'services/app_info_service.dart';
import 'services/preferences_service.dart';
import 'settings_screen.dart';
import 'utils/log_feedback.dart';
import 'widgets/log_tab_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TabbedViewController _tabsController = TabbedViewController([]);
  final ValueNotifier<int> _appMemoryBytes = ValueNotifier<int>(0);
  final Map<Object, WorkspaceTabBinding> _workspaceTabs = {};
  late final TabData _newTabActionTab = TabData(
    id: AppConstants.newTabActionId,
    text: AppConstants.newTabLabel,
    tooltip: AppConstants.newTabTooltip,
    closable: false,
    draggable: false,
    view: const SizedBox.shrink(),
    labelBuilder: (context) => NewTabActionLabel(textStyle: context.textStyle),
  );

  Timer? _memoryRefreshTimer;
  int _nextTabNumber = 1;
  bool _isAdjustingNewTabActionPosition = false;
  bool _ignoreNextNewTabSelection = false;

  bool get _supportsDesktopMenuBar => Platform.isMacOS;

  LogTabController? get _activeController =>
      _tabsController.selectedTab?.value as LogTabController?;

  bool _isNewTabAction(TabData tab) => tab.id == AppConstants.newTabActionId;

  int get _workspaceTabCount =>
      _tabsController.tabs.where((tab) => !_isNewTabAction(tab)).length;

  @override
  void initState() {
    super.initState();
    _tabsController.onTabRemoved = _onTabRemoved;
    _tabsController.onTabReordered = _onTabReordered;
    _tabsController.onTabSelected = _onTabSelected;
    _refreshAppMemory();
    _memoryRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAppMemory();
    });
    _ensureNewTabActionPresent();
    _ensureAtLeastOneTab();
  }

  @override
  void dispose() {
    _memoryRefreshTimer?.cancel();
    _appMemoryBytes.dispose();
    for (final workspaceTab in _workspaceTabs.values.toList()) {
      workspaceTab.dispose();
    }
    _workspaceTabs.clear();
    _tabsController.dispose();
    super.dispose();
  }

  void _refreshAppMemory() {
    final rss = ProcessInfo.currentRss;
    if (_appMemoryBytes.value != rss) {
      _appMemoryBytes.value = rss;
    }
  }

  void _ensureAtLeastOneTab() {
    if (_workspaceTabCount > 0) return;
    _createTab(select: true);
  }

  void _ensureNewTabActionPresent() {
    final newTabActionIndex = _tabsController.tabs.indexWhere(_isNewTabAction);
    if (newTabActionIndex == -1) {
      _tabsController.addTab(_newTabActionTab);
      return;
    }
    _moveNewTabActionToEnd();
  }

  void _moveNewTabActionToEnd() {
    if (_isAdjustingNewTabActionPosition) return;
    final newTabActionIndex = _tabsController.tabs.indexWhere(_isNewTabAction);
    if (newTabActionIndex == -1 ||
        newTabActionIndex == _tabsController.tabs.length - 1) {
      return;
    }

    _isAdjustingNewTabActionPosition = true;
    try {
      _tabsController.reorderTab(
        newTabActionIndex,
        _tabsController.tabs.length,
      );
    } finally {
      _isAdjustingNewTabActionPosition = false;
    }
  }

  FutureOr<bool> _handleTabRemoveRequest(
    BuildContext context,
    int tabIndex,
    TabData tab,
  ) {
    if (!_isNewTabAction(tab) && _workspaceTabCount == 1) {
      _ignoreNextNewTabSelection = true;
    }
    // when removing second last tab; so tab just before new tab; ignore next new tab selection to avoid creating a new tab when the last tab is removed and new tab action gets selected
    if (tabIndex == _tabsController.tabs.length - 2) {
      _ignoreNextNewTabSelection = true;
    }
    return true;
  }

  void _clearNewTabActionSelectionIfNeeded() {
    debugTabs('Clearing new tab action selection if needed');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedTab = _tabsController.selectedTab;
      if (selectedTab != null && _isNewTabAction(selectedTab)) {
        _tabsController.selectedIndex = _tabsController.length - 2;
      }
    });
  }

  bool _isDeviceSelectedInAnotherTab(String deviceId, LogTabController owner) {
    return _workspaceTabs.values.any(
      (workspaceTab) =>
          !identical(workspaceTab.controller, owner) &&
          workspaceTab.controller.selectedDevice?.id == deviceId,
    );
  }

  void _createTab({bool select = true}) {
    final tabNumber = _nextTabNumber++;
    late final LogTabController controller;
    controller = LogTabController(
      id: 'workspace-tab-$tabNumber',
      initialTitle: 'Tab $tabNumber',
      initialSettings: PreferencesService.defaultTabSettings,
      isDeviceSelectedInAnotherTab: (deviceId) =>
          _isDeviceSelectedInAnotherTab(deviceId, controller),
    );

    final tabData = TabData(
      id: controller.id,
      value: controller,
      text: controller.title,
      tooltip: controller.title,
      closable: true,
      keepAlive: true,
      labelBuilder: (context) => WorkspaceTabLabel(
        controller: controller,
        textStyle: context.textStyle,
      ),
      view: LogTabView(
        controller: controller,
        appMemoryBytesListenable: _appMemoryBytes,
        onOpenSettings: _openSettings,
        onShowAbout: _showAboutApp,
      ),
    );

    void syncTabLabel() {
      tabData.text = controller.title;
      tabData.tooltip = controller.title;
    }

    controller.addListener(syncTabLabel);
    _workspaceTabs[tabData.id] = WorkspaceTabBinding(
      tabData: tabData,
      controller: controller,
      syncListener: syncTabLabel,
    );

    final newTabActionIndex = _tabsController.tabs.indexWhere(_isNewTabAction);
    if (newTabActionIndex == -1) {
      _tabsController.addTab(tabData);
      _ensureNewTabActionPresent();
    } else {
      _tabsController.insertTab(newTabActionIndex, tabData);
    }

    if (select) {
      _tabsController.selectedIndex = _tabsController.tabs.indexOf(tabData);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(controller.bootstrapInitialLoad());
    });
    setState(() {});
  }

  void _onTabRemoved(TabData tab) {
    debugTabs('removed: ${tab.text} (${tab.id})');
    if (_isNewTabAction(tab)) {
      _ensureNewTabActionPresent();
      return;
    }

    final workspaceTab = _workspaceTabs.remove(tab.id);
    workspaceTab?.dispose();

    if (_workspaceTabCount == 0) {
      _clearNewTabActionSelectionIfNeeded();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onTabReordered(int oldIndex, int newIndex) {
    debugTabs('reordered: $oldIndex -> $newIndex');
    _moveNewTabActionToEnd();
    if (mounted) {
      setState(() {});
    }
  }

  void _onTabSelected(TabSelection? selection) async {
    debugTabs(
      'selection ${selection?.index}\nworkspaceTabCount: $_workspaceTabCount\nignoreNextNewTabSelection: $_ignoreNextNewTabSelection',
    );
    final selectedTab = selection?.tab;
    if (selectedTab != null && _isNewTabAction(selectedTab)) {
      if (_ignoreNextNewTabSelection && _workspaceTabCount > 0) {
        _ignoreNextNewTabSelection = false;
        _clearNewTabActionSelectionIfNeeded();
        if (mounted) {
          setState(() {});
        }
        return;
      }

      _createTab(select: true);
      return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    setState(() {});
  }

  void _showAboutApp() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppInfoService.appVersion,
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

  Future<void> _handleImportLogs() async {
    final controller = _activeController;
    if (controller == null) return;

    final result = await controller.importLogs();
    if (!mounted || result.cancelled || result.error == null) return;
    _showSnackBar(result.error!);
  }

  Future<void> _handleExportLogs() async {
    final controller = _activeController;
    if (controller == null) return;

    final result = await controller.exportLogs();
    if (!mounted || result.cancelled) return;

    _showSnackBar(formatExportLogsMessage(result));
  }

  void _runOnActiveTab(void Function(LogTabController tab) action) {
    final controller = _activeController;
    if (controller == null) return;
    action(controller);
  }

  List<PlatformMenuItem> _logLevelFilterMenuItems() {
    return buildLogLevelMenuItems(
      onSelected: (value) =>
          _runOnActiveTab((tab) => tab.setSelectedLogLevel(value)),
    );
  }

  List<PlatformMenuItem> _buildDesktopMenus() {
    return [
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(label: 'New Tab', onSelected: _createTab),
              PlatformMenuItem(
                label: 'Import Logs',
                onSelected: () {
                  unawaited(_handleImportLogs());
                },
              ),
              PlatformMenuItem(
                label: 'Export Logs',
                onSelected: () {
                  unawaited(_handleExportLogs());
                },
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(label: 'Settings', onSelected: _openSettings),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Logs',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Reload Devices',
                onSelected: () => _runOnActiveTab((tab) => tab.loadDevices()),
              ),
              PlatformMenuItem(
                label: 'Start / Restart Logcat',
                onSelected: () => _runOnActiveTab((tab) => tab.startLogcat()),
              ),
              PlatformMenuItem(
                label: 'Pause / Resume Logcat',
                onSelected: () =>
                    _runOnActiveTab((tab) => tab.togglePauseResume()),
              ),
              PlatformMenuItem(
                label: 'Clear Logs',
                onSelected: () => _runOnActiveTab((tab) => tab.clearLogs()),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Scroll to End',
                onSelected: () => _runOnActiveTab((tab) => tab.scrollToEnd()),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Search',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Toggle Search',
                onSelected: () =>
                    _runOnActiveTab((tab) => tab.toggleSearchBar()),
              ),
              PlatformMenuItem(
                label: 'Previous Match',
                onSelected: () => _runOnActiveTab((tab) => tab.onSearchPrev()),
              ),
              PlatformMenuItem(
                label: 'Next Match',
                onSelected: () => _runOnActiveTab((tab) => tab.onSearchNext()),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Filter',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Focus Filter Input',
                onSelected: () =>
                    _runOnActiveTab((tab) => tab.focusFilterInputs()),
              ),
              PlatformMenuItem(
                label: 'Clear Filter',
                onSelected: () => _runOnActiveTab((tab) => tab.clearFilter()),
              ),
            ],
          ),
          PlatformMenuItemGroup(members: _logLevelFilterMenuItems()),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Toggle Wrap Text',
                onSelected: () =>
                    _runOnActiveTab((tab) => tab.toggleWrapText()),
              ),
              PlatformMenuItem(
                label: 'Toggle Auto-scroll',
                onSelected: () =>
                    _runOnActiveTab((tab) => tab.toggleAutoScroll()),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About / Version',
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
    final activeController = _activeController;
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    final theme = TabbedViewThemeData.minimalist(
      tabRadius: 8,
      tabStyleResolver: HomeTabsStyleResolver(colorScheme: colorScheme),
    );
    theme.tabsArea.padding = EdgeInsets.zero;
    theme.tabsArea.position = TabBarPosition.top;
    theme.divider = null;
    theme.tabsArea.sideTabsLayout = SideTabsLayout.stacked;

    final content = Shortcuts(
      shortcuts: homePageShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateSearchIntent: CallbackAction<ActivateSearchIntent>(
            onInvoke: (_) {
              activeController?.toggleSearchBar();
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
              child: TabbedViewTheme(
                data: theme,
                child: TabbedView(
                  controller: _tabsController,
                  tabRemoveInterceptor: _handleTabRemoveRequest,
                ),
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
}
