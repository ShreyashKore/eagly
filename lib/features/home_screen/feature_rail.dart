import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../session/device_session_controller.dart';
import 'components/rail_button.dart';
import 'components/rail_footer.dart';

/// Far-left vertical rail listing the features available for a device. The
/// rail is split into two sections: Home (pinned at the top, its own
/// mutually-exclusive view) and the panes below it, each of which opens or
/// closes a pane of the workspace independently — where it opens, and how the
/// panes are arranged, is the workspace's business (see
/// docs/WORKSPACE_LAYOUT.md). Selecting Home swaps the visible view but never
/// closes the other panes underneath — selecting any of them again restores
/// the previous layout. Install opens a file picker. Settings and the app
/// version are pinned to the bottom.
///
/// Whichever section is on screen sits on a raised tray, which slides (and
/// stretches, leading edge first) to the other section when the view
/// switches. While Home has the focus, the panes still open underneath are
/// drawn *parked* — outlined, not filled — so only one section ever looks
/// active.
///
/// Its width and padding follow the app zoom (a text scale), so the labels
/// keep their room as the user zooms rather than being squeezed to fit.
class const FeatureRail({
  super.key,
  required final DeviceSessionController session,
  required final VoidCallback onInstall,
  required final VoidCallback onOpenSettings,
}) extends StatefulWidget {
  @override
  State<FeatureRail> createState() => _FeatureRailState();
}

class _FeatureRailState extends State<FeatureRail>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 200);

  /// Where the tray is: 0 around Home, 1 around the panes.
  late final AnimationController _focus = AnimationController(
    vsync: this,
    value: _focusTarget,
  );

  double get _focusTarget => widget.session.isHomeOpen ? 0 : 1;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(FeatureRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
      // Another device's rail: its view is already settled, nothing moved.
      _focus.value = _focusTarget;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final target = _focusTarget;
    if (_focus.value == target && !_focus.isAnimating) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _focus.value = target;
    } else {
      _focus.animateTo(
        target,
        duration: _slideDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final homeOpen = session.isHomeOpen;
        return Container(
          width: context.scaled(72),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          padding: EdgeInsets.all(context.scaled(4)),
          child: Column(
            children: [
              Expanded(
                child: CustomMultiChildLayout(
                  delegate: _RailSectionsLayout(_focus),
                  children: [
                    // Painted first, so it sits beneath both sections.
                    LayoutId(id: _RailSection.tray, child: const _FocusTray()),
                    LayoutId(
                      id: _RailSection.home,
                      child: Padding(
                        padding: EdgeInsets.all(context.scaled(3)),
                        child: RailButton(
                          icon: Icons.home_outlined,
                          activeIcon: Icons.home_rounded,
                          label: 'Home',
                          isActive: homeOpen,
                          tooltip: !homeOpen
                              ? 'Show device home'
                              : session.workspaceLayout.isEmpty
                              ? 'Device home'
                              : 'Hide device home',
                          onTap: session.toggleHome,
                        ),
                      ),
                    ),
                    LayoutId(
                      id: _RailSection.panes,
                      child: _PanesSection(
                        session: session,
                        onInstall: widget.onInstall,
                      ),
                    ),
                  ],
                ),
              ),
              RailButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                isActive: false,
                tooltip: 'Settings',
                onTap: widget.onOpenSettings,
              ),
              const RailFooter(),
            ],
          ),
        );
      },
    );
  }
}

enum _RailSection { tray, home, panes }

/// Stacks Home over the panes and lays the tray around whichever one has the
/// focus, morphing between the two as [focus] runs. The edge heading towards
/// the new section moves first and the other catches up, so the tray
/// stretches as it slides — it reads as the focus *moving*, not two boxes
/// cross-fading. Done in layout, not with measured keys, so the tray never
/// lags a frame behind a resize or a button appearing.
class _RailSectionsLayout extends MultiChildLayoutDelegate {
  _RailSectionsLayout(this.focus) : super(relayout: focus);

  final Animation<double> focus;

  static const _top = 4.0;
  static const _gap = 8.0;

  @override
  void performLayout(Size size) {
    final width = BoxConstraints.tightFor(width: size.width);

    final homeSize = layoutChild(
      _RailSection.home,
      width.copyWith(maxHeight: size.height - _top),
    );
    final home = const Offset(0, _top) & homeSize;
    positionChild(_RailSection.home, home.topLeft);

    final panesTop = home.bottom + _gap;
    final panesSize = layoutChild(
      _RailSection.panes,
      width.copyWith(maxHeight: (size.height - panesTop).clamp(0, size.height)),
    );
    final panes = Offset(0, panesTop) & panesSize;
    positionChild(_RailSection.panes, panes.topLeft);

    // Heading down (towards the panes) the bottom edge leads; heading up the
    // top edge does. Easing the bottom out and the top in gives both, since
    // the same curves run backwards on the way up.
    final t = focus.value;
    final top = _lerp(home.top, panes.top, Curves.easeInQuad.transform(t));
    final bottom = _lerp(
      home.bottom,
      panes.bottom,
      Curves.easeOutQuad.transform(t),
    );
    layoutChild(
      _RailSection.tray,
      BoxConstraints.tight(Size(size.width, bottom - top)),
    );
    positionChild(_RailSection.tray, Offset(0, top));
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRelayout(_RailSectionsLayout oldDelegate) =>
      oldDelegate.focus != focus;
}

/// The raised card under the section that is on screen.
class const _FocusTray() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// The panes section: a faint frame of its own (so it reads as a group even
/// while the tray is up at Home), a caption naming it, and one button per
/// pane.
class const _PanesSection({
  required final DeviceSessionController session,
  required final VoidCallback onInstall,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final homeOpen = session.isHomeOpen;

    RailButton pane({
      required IconData icon,
      IconData? activeIcon,
      required String label,
      required String name,
      required bool isOpen,
      required String openTooltip,
      required VoidCallback onTap,
      bool available = true,
      String? unavailableTooltip,
    }) {
      final usable = available || isOpen;
      return RailButton(
        icon: icon,
        activeIcon: activeIcon,
        label: label,
        isActive: isOpen && !homeOpen,
        parked: isOpen && homeOpen,
        enabled: usable,
        tooltip: !usable
            ? unavailableTooltip ?? openTooltip
            : !isOpen
            ? openTooltip
            // While Home is up, tapping an open pane brings the workspace
            // back rather than closing it (`togglePane`).
            : homeOpen
            ? 'Back to $name'
            : 'Hide $name',
        onTap: usable ? onTap : null,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.6),
        ),
      ),
      padding: EdgeInsets.all(context.scaled(3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanesCaption(session: session),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                spacing: 4,
                children: [
                  pane(
                    icon: Icons.article_outlined,
                    activeIcon: Icons.article,
                    label: 'Logs',
                    name: 'logs',
                    isOpen: session.isLogsOpen,
                    openTooltip: 'View device logs',
                    onTap: session.toggleLogs,
                  ),
                  // To make mirroring discoverable, we show the button even if
                  // the device doesn't support it, but disable it and show a
                  // tooltip explaining why.
                  pane(
                    icon: Icons.mobile_screen_share_outlined,
                    activeIcon: Icons.mobile_screen_share,
                    label: 'Mirror',
                    name: 'mirror',
                    isOpen: session.isMirrorOpen,
                    available: session.canMirror,
                    openTooltip: 'Open mirror',
                    unavailableTooltip: session.mirrorUnavailableReason,
                    onTap: session.toggleMirror,
                  ),
                  if (session.canReadCrashReports)
                    pane(
                      icon: Icons.bug_report_outlined,
                      activeIcon: Icons.bug_report,
                      label: 'Crashes',
                      name: 'crash reports',
                      isOpen: session.isCrashReportsOpen,
                      openTooltip: 'Read crash reports',
                      onTap: session.toggleCrashReports,
                    ),
                  pane(
                    icon: Icons.folder_outlined,
                    activeIcon: Icons.folder,
                    label: 'Files',
                    name: 'files',
                    isOpen: session.isFilesOpen,
                    available: session.canManageFiles,
                    openTooltip: 'Browse device files',
                    unavailableTooltip: 'Connect the device to browse files',
                    onTap: session.toggleFiles,
                  ),
                  pane(
                    icon: Icons.apps_outlined,
                    activeIcon: Icons.apps,
                    label: 'Apps',
                    name: 'apps',
                    isOpen: session.isAppsOpen,
                    available: session.canManageApps,
                    openTooltip: 'Manage installed apps',
                    unavailableTooltip: 'Connect the device to manage apps',
                    onTap: session.toggleApps,
                  ),
                  if (session.canRunUtilities)
                    pane(
                      icon: Icons.handyman_outlined,
                      activeIcon: Icons.handyman,
                      label: 'Utilities',
                      name: 'utilities',
                      isOpen: session.isUtilitiesOpen,
                      openTooltip: 'Run device commands',
                      onTap: session.toggleUtilities,
                    ),
                  if (session.canUseTerminal)
                    pane(
                      icon: Icons.terminal_outlined,
                      activeIcon: Icons.terminal,
                      label: 'Terminal',
                      name: 'terminal',
                      isOpen: session.isTerminalOpen,
                      openTooltip: 'Type adb / idevice commands',
                      onTap: session.toggleTerminal,
                    ),
                  if (session.canInspectNetwork)
                    pane(
                      icon: Icons.http,
                      label: 'Network',
                      name: 'network',
                      isOpen: session.isNetworkOpen,
                      openTooltip: 'Inspect HTTP traffic',
                      onTap: session.toggleNetwork,
                    ),
                  if (session.canInspectLayout)
                    pane(
                      icon: Icons.account_tree_outlined,
                      activeIcon: Icons.account_tree,
                      label: 'Layout',
                      name: 'layout inspector',
                      isOpen: session.isLayoutInspectorOpen,
                      openTooltip: 'Inspect what is on screen',
                      onTap: session.toggleLayoutInspector,
                    ),
                  // Install is an action, not a pane: it never parks.
                  RailButton(
                    icon: Icons.system_update_outlined,
                    label: session.isInstallingApp ? 'Installing' : 'Install',
                    isActive: session.isInstallingApp,
                    busy: session.isInstallingApp,
                    enabled: session.isConnected,
                    tooltip: session.isInstallingApp
                        ? (session.installingAppName == null
                              ? 'Installing…'
                              : 'Installing ${session.installingAppName}…')
                        : session.isConnected
                        ? 'Install app on this device'
                        : 'Connect the device to install an app',
                    onTap: session.isConnected && !session.isInstallingApp
                        ? onInstall
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "PANES" over the panes section: names the second half of the rail, lights
/// up with it, and — while Home is up with panes open underneath — is a way
/// back to them.
class const _PanesCaption({required final DeviceSessionController session})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final focused = !session.isHomeOpen;
    final canReturn = session.isHomeOpen && !session.workspaceLayout.isEmpty;
    final motion = (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : const Duration(milliseconds: 140);

    final caption = Padding(
      padding: EdgeInsets.symmetric(vertical: context.scaled(4)),
      child: SizedBox(
        width: double.infinity,
        child: AnimatedDefaultTextStyle(
          duration: motion,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: focused
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('PANES', textAlign: TextAlign.center),
          ),
        ),
      ),
    );

    if (!canReturn) return caption;
    return Tooltip(
      message: 'Back to open panes',
      child: InkWell(
        onTap: session.closeHome,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        child: caption,
      ),
    );
  }
}
