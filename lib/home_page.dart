import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:tabbed_view/tabbed_view.dart';

import 'controllers/log_tab_controller.dart';
import 'data/log_view_mode.dart';
import 'services/app_info_service.dart';
import 'services/preferences_service.dart';
import 'settings_screen.dart';
import 'widgets/log_tab_view.dart';

/// Intent fired by the Ctrl+F / Cmd+F keyboard shortcut.
class _ActivateSearchIntent extends Intent {
  const _ActivateSearchIntent();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TabbedViewController _tabsController = TabbedViewController([]);
  final ValueNotifier<int> _appMemoryBytes = ValueNotifier<int>(0);
  final Map<Object, _WorkspaceTab> _workspaceTabs = {};

  Timer? _memoryRefreshTimer;
  int _nextTabNumber = 1;

  bool get _supportsDesktopMenuBar => Platform.isMacOS;

  LogTabController? get _activeController =>
      _tabsController.selectedTab?.value as LogTabController?;

  @override
  void initState() {
    super.initState();
    _tabsController.onTabRemoved = _onTabRemoved;
    _tabsController.onTabSelected = (_) {
      if (mounted) {
        setState(() {});
      }
    };
    _refreshAppMemory();
    _memoryRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAppMemory();
    });
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
    if (_tabsController.tabs.isNotEmpty) return;
    _createTab(select: true);
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
    _workspaceTabs[tabData.id] = _WorkspaceTab(
      tabData: tabData,
      controller: controller,
      syncListener: syncTabLabel,
    );

    _tabsController.addTab(tabData);
    if (select) {
      _tabsController.selectedIndex = _tabsController.tabs.length - 1;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(controller.bootstrapInitialLoad());
    });
    setState(() {});
  }

  void _onTabRemoved(TabData tab) {
    final workspaceTab = _workspaceTabs.remove(tab.id);
    workspaceTab?.dispose();
    if (_tabsController.tabs.isEmpty) {
      _createTab(select: true);
    } else {
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
      applicationName: 'ADB Logcat',
      applicationVersion: AppInfoService.appVersion,
      children: const [Text('Desktop log viewer for ADB logcat output.')],
    );
  }

  void _runOnActiveTab(void Function(LogTabController tab) action) {
    final controller = _activeController;
    if (controller == null) return;
    action(controller);
  }

  List<PlatformMenuItem> _logLevelFilterMenuItems() {
    const levels = [
      ('E', 'Error'),
      ('W', 'Warning'),
      ('I', 'Info'),
      ('D', 'Debug'),
      ('V', 'Verbose'),
    ];

    return [
      for (final (value, label) in levels)
        PlatformMenuItem(
          label: '$label ($value)',
          onSelected: () =>
              _runOnActiveTab((tab) => tab.setSelectedLogLevel(value)),
        ),
    ];
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
                onSelected: () => _runOnActiveTab((tab) => tab.importLogs()),
              ),
              PlatformMenuItem(
                label: 'Export Logs',
                onSelected: () => _runOnActiveTab((tab) => tab.exportLogs()),
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
              PlatformMenuItem(
                label: 'Cycle View Mode',
                onSelected: () => _runOnActiveTab((tab) => tab.cycleViewMode()),
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

  String _activeViewModeLabel(LogViewMode mode) {
    return switch (mode) {
      LogViewMode.text => 'Text',
      LogViewMode.dataTable => 'Table',
      LogViewMode.worksheet => 'Worksheet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeController = _activeController;
    final theme = TabbedViewThemeData.minimalist(
      tabRadius: 8,
    );
    theme.tabsArea.padding = EdgeInsets.symmetric(horizontal: 8);
    theme.tabsArea.position = TabBarPosition.top;
    theme.tabsArea.sideTabsLayout = SideTabsLayout.stacked;

    final content = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _ActivateSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _ActivateSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ActivateSearchIntent: CallbackAction<_ActivateSearchIntent>(
            onInvoke: (_) {
              activeController?.toggleSearchBar();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F6FB),
            body: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ],
                ),
                child: TabbedViewTheme(
                  data: theme,
                  child: TabbedView(
                    controller: _tabsController,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Center(
                        child: FilledButton.tonalIcon(
                          style: ButtonStyle(
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          onPressed: _createTab,
                          icon: const Icon(Icons.add),
                          label: const Text('New tab'),
                        ),
                      ),
                    ),
                  ),
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

class _WorkspaceTab {
  _WorkspaceTab({
    required this.tabData,
    required this.controller,
    required this.syncListener,
  });

  final TabData tabData;
  final LogTabController controller;
  final VoidCallback syncListener;

  void dispose() {
    controller.removeListener(syncListener);
    controller.dispose();
  }
}
