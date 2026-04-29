class IosDeviceInfo {
  const IosDeviceInfo({
    required this.deviceId,
    required this.status,
    this.deviceName,
    this.productName,
    this.hardwareModel,
    this.productType,
  });

  final String deviceId;
  final String status;
  final String? deviceName;
  final String? productName;
  final String? hardwareModel;
  final String? productType;

  bool get isAvailable => status == 'device';

  IosDeviceInfo copyWith({
    String? deviceId,
    String? status,
    String? deviceName,
    String? productName,
    String? hardwareModel,
    String? productType,
  }) {
    return IosDeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      productName: productName ?? this.productName,
      hardwareModel: hardwareModel ?? this.hardwareModel,
      productType: productType ?? this.productType,
    );
  }
}
