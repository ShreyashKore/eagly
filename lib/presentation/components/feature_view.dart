import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';
import '../theme/app_theme.dart';

import 'overflow_toolbar.dart';
import 'workspace_pane_scope.dart';
import 'snack_bars.dart';

/// Base class for the per-device feature panes (logs, mirror, crash reports,
/// file manager, device home) — the view counterpart of `FeatureController`.
///
/// A feature view renders its feature controller(s) and gets the shared pane
/// plumbing for free: the [onClose] callback, a rebuild whenever
/// [FeatureViewState.listenable] notifies, a snackbar helper, and the standard
/// pane chrome ([FeaturePane], [FeatureViewHeader], [FeatureSubBar],
/// [FeatureStatusBar]).
abstract class const FeatureView({
  super.key,

  /// Hides the pane (handled by the device screen). `null` for panes that
  /// cannot be closed (e.g. device home).
  final VoidCallback? onClose,
}) extends StatefulWidget {}

/// Base [State] for a [FeatureView]: rebuilds [buildContent] whenever
/// [listenable] notifies. Subclasses implement [buildContent] instead of
/// overriding [build].
abstract class FeatureViewState<T extends FeatureView> extends State<T> {
  /// The listenable this view rebuilds on — typically the feature controller.
  /// When `null`, [buildContent] is built directly.
  Listenable? get listenable => null;

  /// Builds the pane's content. Called inside a [ListenableBuilder] when
  /// [listenable] is non-null.
  Widget buildContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable == null) return buildContent(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => buildContent(context),
    );
  }

  /// Shows [message] in a snackbar; safe to call after async gaps. A `null`
  /// [message] — an action that had nothing to report — shows nothing.
  void showSnackBar(String? message) {
    if (message == null || !mounted) return;
    showMessageSnackBar(context, message);
  }
}

/// The standard feature-pane shell: [header] on top, [body] filling the rest,
/// and an optional [statusBar] at the bottom, on the pane background color.
class const FeaturePane({
  super.key,
  final Widget? header,
  required final Widget body,
  final Widget? statusBar,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) header!,
          Expanded(child: body),
          if (statusBar != null) statusBar!,
        ],
      ),
    );
  }
}

/// The one header every feature pane uses — see "Pane chrome" in AGENTS.md.
///
/// A 48-dip bar on the chrome surface, its slots always in this order:
///
/// `grip · leading · title (or tabs) · primary | actions · ⋯ · trailing · ×`
///
/// - [leading]: navigation only — back, up — drawn before the title.
/// - [title]: names the pane, or the item it has drilled into (with a back
///   button in [leading]). [tabs] replaces it for panes that hold several
///   sessions (Logs, Terminal); the pane is still named by [title] in the
///   grip's tooltip and in its workspace tab chip.
/// - [primary]: the controls that drive the pane — start/stop, pause,
///   refresh, capture, clear. They open the right-hand group and never
///   collapse.
/// - [actions]: everything else, least important last. Panes are resizable
///   and arranged freely, so these collapse into an overflow menu once the
///   header runs out of room (see [OverflowToolbar]).
/// - [trailing]: controls that can't become a menu entry (their own popup).
///
/// Every button in the header is drawn by the header itself, from a
/// [ToolbarAction], so they all share one size and style.
///
/// Hosted in the device workspace, the header is also the pane's title bar:
/// a [PaneGrip] leads it and the title area drags the pane. While the pane
/// sits in a tab group its tab chip is the title bar — title, close button,
/// drag handle — so the header keeps only the rest, and is not drawn at all
/// when nothing is left (see [WorkspacePaneScope]).
class const FeatureViewHeader({
  super.key,
  required final String title,

  /// Shown in place of [title] — a pane's own session tabs.
  final Widget? tabs,

  /// Navigation buttons before the title (back, up).
  final List<ToolbarAction> leading = const [],

  /// The pane's main controls; always visible, at the start of the
  /// right-hand group.
  final List<ToolbarAction> primary = const [],

  /// Secondary actions; the last ones collapse into the overflow menu first.
  final List<ToolbarAction> actions = const [],

  /// Widgets pinned between the actions and the close button — for controls
  /// that cannot become a menu entry (e.g. their own popup menu).
  final List<Widget> trailing = const [],
  final VoidCallback? onClose,
  final String closeTooltip = 'Close pane',
}) extends StatelessWidget {
  /// The header's height before UI scaling.
  static const double height = 48;

  /// Size of every icon in the header.
  static const double iconSize = 20;

  /// Narrowest the title (or tab strip) gets before actions collapse.
  static const double _titleMinWidth = 56;
  static const double _tabsMinWidth = 120;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = WorkspacePaneScope.maybeOf(context);
    final movable = scope?.showsGrip ?? false;
    if ((scope?.isTabbed ?? false) &&
        tabs == null &&
        leading.isEmpty &&
        primary.isEmpty &&
        actions.isEmpty &&
        trailing.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: context.scaled(height),
      padding: EdgeInsets.fromLTRB(movable ? 4 : 12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: OverflowToolbar(
        spacing: 2,
        iconSize: iconSize,
        leading: [
          if (movable) const PaneGrip(),
          for (final action in leading) _button(action),
          if (leading.isNotEmpty) const SizedBox(width: 4),
        ],
        // The title slot is the pane's title bar: it drags the pane, tabs
        // included (a chip only takes clicks), as does the space after them.
        flexible: PaneDragArea(
          slop: paneToolbarDragSlop,
          child: Align(
            alignment: Alignment.centerLeft,
            child:
                tabs ??
                (WorkspacePaneScope.showsOwnTitle(context)
                    ? Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox.shrink()),
          ),
        ),
        flexibleMinWidth: tabs != null ? _tabsMinWidth : _titleMinWidth,
        pinnedCount: primary.length,
        actions: [...primary, ...actions],
        trailing: [
          ...trailing,
          if (onClose != null && WorkspacePaneScope.showsOwnClose(context))
            AppIconButton(
              tooltip: closeTooltip,
              iconSize: iconSize,
              onPressed: onClose,
              icon: Icons.close,
            ),
        ],
      ),
    );
  }

  static Widget _button(ToolbarAction action) => AppIconButton(
    tooltip: action.tooltip ?? action.label,
    iconSize: iconSize,
    isActive: action.isActive,
    color: action.color,
    onPressed: action.onPressed,
    busy: action.busy,
    icon: action.icon,
  );
}

/// The strip under a [FeatureViewHeader] for a pane's search, filters,
/// breadcrumbs or find bar: the header's surface with a divider below, so
/// header and sub-bar read as one block of chrome above the content.
class const FeatureSubBar({
  super.key,
  required final Widget child,
  final EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  ),
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // Hover ink inside the bar paints on this, above the bar's colour.
      child: Material(
        type: MaterialType.transparency,
        child: fieldTheme(context, child),
      ),
    );
  }

  /// [child] with text fields filled in [EaglyTheme.chromeFieldColor], the
  /// default for any field on pane chrome — the theme's own fill is the
  /// chrome's colour, which would lose the field against the bar.
  static Widget fieldTheme(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    // A bare MaterialApp (a widget test) has no Eagly tokens to apply.
    final tokens = theme.extension<EaglyTheme>();
    if (tokens == null) return child;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: tokens.chromeFieldColor,
        ),
      ),
      child: child,
    );
  }
}

/// Full-width bar shown at the bottom of a feature pane.
///
/// Panes are resizable, so the bar scrolls sideways once its readouts no
/// longer fit — nothing is dropped or truncated. While they do fit the row
/// behaves normally, so a [Spacer] still pushes the trailing group to the
/// right edge.
class const FeatureStatusBar({
  super.key,
  required final List<Widget> children,
  final EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  ),
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return ScrollConfiguration(
            // A scrollbar would sit on top of a bar this thin; dragging with
            // the mouse replaces it as the affordance.
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: PointerDeviceKind.values.toSet(),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Stretch to the full width when the content is narrower,
                // otherwise let the row take its natural width and scroll.
                constraints: BoxConstraints(
                  minWidth: width.isFinite ? width : 0,
                ),
                child: IntrinsicWidth(child: Row(children: children)),
              ),
            ),
          );
        },
      ),
    );
  }
}
