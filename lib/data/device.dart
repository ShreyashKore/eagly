enum DevicePlatform { android, ios }

enum DeviceConnectionState { connected, disconnected }

class Device {
  final String id;
  final String status;
  final String? model;
  final String? name;
  final DevicePlatform platform;
  final DeviceConnectionState connectionState;

  Device(
    this.id,
    this.status, {
    this.model,
    this.name,
    this.platform = DevicePlatform.android,
    this.connectionState = DeviceConnectionState.connected,
  });

  bool get isAndroid => platform == DevicePlatform.android;
  bool get isIos => platform == DevicePlatform.ios;
  bool get isConnected => connectionState == DeviceConnectionState.connected;
  bool get isDisconnected => !isConnected;

  String get statusLabel => isDisconnected ? 'disconnected' : status;

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

  Device copyWith({
    String? id,
    String? status,
    String? model,
    String? name,
    DevicePlatform? platform,
    DeviceConnectionState? connectionState,
  }) {
    return Device(
      id ?? this.id,
      status ?? this.status,
      model: model ?? this.model,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      connectionState: connectionState ?? this.connectionState,
    );
  }

  @override
  String toString() {
    return 'Device(id: $id, status: $status, model: $model, name: $name, platform: $platform, connectionState: $connectionState)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Device &&
        other.id == id &&
        other.status == status &&
        other.model == model &&
        other.name == name &&
        other.platform == platform &&
        other.connectionState == connectionState;
  }

  @override
  int get hashCode =>
      Object.hash(id, status, model, name, platform, connectionState);
}
