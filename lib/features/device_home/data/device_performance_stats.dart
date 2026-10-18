class const CpuStats({
  required final int coreCount,
  required final double loadAverage1m,
  required final double loadAverage5m,
  required final double loadAverage15m,
}) {
  double get utilisationPercent =>
      coreCount > 0 ? (loadAverage1m / coreCount * 100).clamp(0, 100) : 0;
}

class const MemoryStats({
  required final int totalKb,
  required final int availableKb,
  required final int freeKb,
}) {
  int get usedKb => (totalKb - availableKb).clamp(0, totalKb);
  double get usagePercent =>
      totalKb > 0 ? (usedKb / totalKb * 100).clamp(0, 100) : 0;
}

class const DevicePerformanceStats({
  final CpuStats? cpu,
  final MemoryStats? memory,
}) {
  bool get isEmpty => cpu == null && memory == null;
}
