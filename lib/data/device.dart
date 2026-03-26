class Device {
  final String id;
  final String status;

  Device(this.id, this.status);

  @override
  String toString() {
    return 'Device(id: $id, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Device &&
      other.id == id &&
      other.status == status;
  }

  @override
  int get hashCode => id.hashCode ^ status.hashCode;
}
