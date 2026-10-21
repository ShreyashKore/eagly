/// Why the device's copy of an app blocks installing another one over it.
enum AppInstallConflictKind {
  /// The installed copy is signed with a different key.
  signature,

  /// The installed copy has a higher version code.
  downgrade,
}

/// An install that failed only because the device already holds
/// [packageName] in a form the package manager won't replace in place.
/// Uninstalling that copy first clears it, at the cost of its data, which is
/// why that is offered rather than done.
class const AppInstallConflict({
  required final AppInstallConflictKind kind,
  required final String packageName,
});
