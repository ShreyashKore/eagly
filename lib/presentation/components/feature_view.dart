import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Base class for the per-device feature panes (logs, mirror, crash reports,
/// file manager, device home) — the view counterpart of `FeatureController`.
///
/// A feature view renders its feature controller(s) and gets the shared pane
/// plumbing for free: the [onClose] callback, a rebuild whenever
/// [FeatureViewState.listenable] notifies, a snackbar helper, and the standard
/// pane chrome ([FeaturePane], [FeatureViewHeader], [FeatureStatusBar]).
abstract class FeatureView extends StatefulWidget {
  const FeatureView({super.key, this.onClose});

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
class FeaturePane extends StatelessWidget {
  const FeaturePane({
    super.key,
    this.header,
    required this.body,
    this.statusBar,
  });

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
/// [actions], then the close button when [onClose] is non-null.
class FeatureViewHeader extends StatelessWidget {
  const FeatureViewHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.onClose,
    this.closeTooltip = 'Close pane',
  });

  final String title;

  /// Optional widget before the title (e.g. a back button).
  final Widget? leading;

  /// Action buttons shown between the title and the close button.
  final List<Widget> actions;

  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: context.scaled(48),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
          if (onClose != null)
            IconButton(
              tooltip: closeTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

/// Full-width bar shown at the bottom of a feature pane.
class FeatureStatusBar extends StatelessWidget {
  const FeatureStatusBar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: padding,
      child: Row(children: children),
    );
  }
}
