class CpuStats {
  const CpuStats({
    required this.coreCount,
    required this.loadAverage1m,
    required this.loadAverage5m,
    required this.loadAverage15m,
  });

  final int coreCount;
  final double loadAverage1m;
  final double loadAverage5m;
  final double loadAverage15m;

  double get utilisationPercent =>
      coreCount > 0 ? (loadAverage1m / coreCount * 100).clamp(0, 100) : 0;
}

class MemoryStats {
  const MemoryStats({
    required this.totalKb,
    required this.availableKb,
    required this.freeKb,
  });

  final int totalKb;
  final int availableKb;
  final int freeKb;

  int get usedKb => (totalKb - availableKb).clamp(0, totalKb);
  double get usagePercent =>
      totalKb > 0 ? (usedKb / totalKb * 100).clamp(0, 100) : 0;
}

class DevicePerformanceStats {
  const DevicePerformanceStats({this.cpu, this.memory});

  final CpuStats? cpu;
  final MemoryStats? memory;

  bool get isEmpty => cpu == null && memory == null;
}
