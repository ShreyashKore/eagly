import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_repository.dart';
import '../services/device_session_service.dart';
import '../ui/log_tab_view/log_tab_controller_factory.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository.instance;
});

final deviceSessionServiceFactoryProvider =
    Provider<DeviceSessionServiceFactory>((ref) {
      return DeviceSessionService.new;
    });

final logTabControllerFactoryProvider = Provider<LogTabControllerFactory>((ref) {
  return LogTabControllerFactory(
    deviceRepository: ref.watch(deviceRepositoryProvider),
    createDeviceSessionService: ref.watch(deviceSessionServiceFactoryProvider),
  );
});

