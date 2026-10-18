import 'package:flutter/foundation.dart';

/// A hardware profile `avdmanager create avd -d` accepts — screen size,
/// density and the rest of what makes a "Pixel 7" a Pixel 7.
@immutable
class const DeviceProfile({
  /// What `-d` takes. Usually a slug (`pixel_7`), but older profiles carry
  /// their display name instead, spaces and all (`Galaxy Nexus`) — which is
  /// why arguments are passed as a list and never through a shell.
  required final String id,
  required final String name,
  final String? oem,

  /// The device class this profile belongs to (`android-tv`, `android-wear`,
  /// …). Absent for phones and tablets, which is the majority.
  final String? tag,
}) {
  bool get isHandheld => tag == null;

  /// `Pixel 7 · Google`
  String get label => oem == null || oem!.isEmpty ? name : '$name · $oem';

  @override
  bool operator ==(Object other) =>
      other is DeviceProfile &&
      other.id == id &&
      other.name == name &&
      other.oem == oem &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(id, name, oem, tag);

  @override
  String toString() => 'DeviceProfile($id)';
}
