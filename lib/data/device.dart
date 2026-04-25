enum DevicePlatform { android, ios }

class Device {
  final String id;
  final String status;
  final String? model;
  final String? name;
  final DevicePlatform platform;

  Device(
    this.id,
    this.status, {
    this.model,
    this.name,
    this.platform = DevicePlatform.android,
  });

  bool get isAndroid => platform == DevicePlatform.android;
  bool get isIos => platform == DevicePlatform.ios;

  String get displayName {
    if (model != null && name != null) {
      return '$model ($name)';
    } else if (model != null) {
      return model!;
    } else if (name != null) {
      return name!;
    }
    return id;
  }

  @override
  String toString() {
    return 'Device(id: $id, status: $status, model: $model, name: $name, platform: $platform)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Device &&
        other.id == id &&
        other.status == status &&
        other.model == model &&
        other.name == name &&
        other.platform == platform;
  }

  @override
  int get hashCode => Object.hash(id, status, model, name, platform);
}
