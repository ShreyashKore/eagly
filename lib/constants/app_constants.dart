class AppConstants {
  static const appName = 'Eagly';
  static const appDescription =
      'Desktop log viewer for Android logcat and iOS syslog output.';
  static const repoOwner = 'ShreyashKore';
  static const repoName = 'eagly';
  static const repoUrl = 'https://github.com/$repoOwner/$repoName';

  /// Identifier + label for the synthetic device-less "Imported Logs" workspace
  /// session that hosts log files opened without a connected device.
  static const importedWorkspaceId = '__imported-logs__';
  static const importedWorkspaceLabel = 'Imported Logs';

  static const newTabActionId = '__new-tab-action__';
  static const newTabLabel = 'New tab';
  static const newTabTooltip = 'Create a new tab';
  static const fontSizeSnackBarWidth = 120.0;

  /// Floating snack bars stretch to the window width by default, which reads
  /// badly on a maximised desktop window. [snackBarMaxWidth] caps them (they
  /// stay centered); [snackBarSideMargin] is the gutter kept on either side
  /// once the window is narrower than that cap.
  static const snackBarMaxWidth = 560.0;
  static const snackBarSideMargin = 24.0;
  static const snackBarMinWidth = 200.0;
}
