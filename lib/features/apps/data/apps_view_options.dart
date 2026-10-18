/// How the Apps pane lays out its inventory.
enum AppsViewMode {
  /// Launcher-style icon grid.
  grid,

  /// One row per app with its details (package, version, install dates).
  list;

  static AppsViewMode fromStored(String? name) =>
      values.firstWhere((mode) => mode.name == name, orElse: () => grid);
}

/// App icon size in the Apps pane, shared by the grid, the list and the
/// recently-installed row.
enum AppIconSize(
  /// Icon edge length in logical pixels.
  final double extent,
  final String label,
) {
  small(40, 'Small'),
  medium(52, 'Medium'),
  large(72, 'Large');

  static AppIconSize fromStored(String? name) =>
      values.firstWhere((size) => size.name == name, orElse: () => medium);
}
