import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_icon_button.dart';
import '../theme/app_theme.dart';

import 'overflow_toolbar.dart';
import 'workspace_pane_scope.dart';

/// Base class for the per-device feature panes (logs, mirror, crash reports,
/// file manager, device home) — the view counterpart of `FeatureController`.
///
/// A feature view renders its feature controller(s) and gets the shared pane
/// plumbing for free: the [onClose] callback, a rebuild whenever
/// [FeatureViewState.listenable] notifies, a snackbar helper, and the standard
/// pane chrome ([FeaturePane], [FeatureViewHeader], [FeatureStatusBar]).
abstract class const FeatureView({super.key, this.onClose})
    extends StatefulWidget {
  /// Hides the pane (handled by the device screen). `null` for panes that
  /// cannot be closed (e.g. device home).
  final VoidCallback? onClose;

  /// Shows [message] in a snackbar, replacing the current one. Static so
  /// deeply-nested pane content can use it with any [BuildContext].
  static void showSnackBar(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

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

  /// Shows [message] in a snackbar; safe to call after async gaps.
  void showSnackBar(String message) {
    if (!mounted) return;
    FeatureView.showSnackBar(context, message);
  }
}

/// The standard feature-pane shell: [header] on top, [body] filling the rest,
/// and an optional [statusBar] at the bottom, on the pane background color.
class const FeaturePane({
  super.key,
  this.header,
  required this.body,
  this.statusBar,
}) extends StatelessWidget {
  final Widget? header;
  final Widget body;
  final Widget? statusBar;

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

/// The standard 48-dip feature-pane header: [title] on the left, then
/// [actions], then the close button when [onClose] is non-null. Panes are
/// resizable and arranged freely, so the actions collapse into an overflow
/// menu once the header runs out of room (see [OverflowToolbar]).
///
/// Hosted in the device workspace, the header is also the pane's title bar:
/// a [PaneGrip] leads it and the title area drags the pane. While the pane
/// sits in a tab group its tab chip is the title bar — title, close button,
/// drag handle — so the header keeps only its actions, and is not drawn at
/// all when it has none (see [WorkspacePaneScope]).
class const FeatureViewHeader({
  super.key,
  required this.title,
  this.leading,
  this.actions = const [],
  this.trailing = const [],
  this.onClose,
  this.closeTooltip = 'Close pane',
}) extends StatelessWidget {
  final String title;

  /// Optional widget before the title (e.g. a back button).
  final Widget? leading;

  /// Action buttons shown between the title and the close button. The last
  /// ones collapse into the overflow menu first.
  final List<ToolbarAction> actions;

  /// Widgets pinned between the actions and the close button — for controls
  /// that cannot become a menu entry (e.g. their own popup menu).
  final List<Widget> trailing;

  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = WorkspacePaneScope.maybeOf(context);
    final movable = scope?.showsGrip ?? false;
    if ((scope?.isTabbed ?? false) &&
        leading == null &&
        actions.isEmpty &&
        trailing.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: context.scaled(48),
      padding: EdgeInsets.fromLTRB(movable ? 4 : 12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: OverflowToolbar(
        spacing: 0,
        iconSize: 24,
        leading: [
          if (movable) ...[const PaneGrip(), const SizedBox(width: 4)],
          if (leading != null) leading!,
        ],
        flexible: PaneDragArea(
          child: Align(
            alignment: Alignment.centerLeft,
            child: WorkspacePaneScope.showsOwnTitle(context)
                ? Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        flexibleMinWidth: 56,
        actions: actions,
        trailing: [
          ...trailing,
          if (onClose != null && WorkspacePaneScope.showsOwnClose(context))
            AppIconButton(
              tooltip: closeTooltip,
              iconSize: 20,
              onPressed: onClose,
              icon: Icons.close,
            ),
        ],
      ),
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
  required this.children,
  this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
}) extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

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
