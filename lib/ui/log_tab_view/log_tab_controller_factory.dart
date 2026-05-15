import 'package:flutter/foundation.dart';

import '../../data/log_tab_settings.dart';
import '../../services/device_repository.dart';
import '../../services/device_session_service.dart';
import 'log_tab_controller.dart';

typedef DeviceSessionServiceFactory = DeviceSessionService Function();

class LogTabControllerFactory {
  const LogTabControllerFactory({
    required DeviceRepository deviceRepository,
    required DeviceSessionServiceFactory createDeviceSessionService,
  }) : _deviceRepository = deviceRepository,
       _createDeviceSessionService = createDeviceSessionService;

  final DeviceRepository _deviceRepository;
  final DeviceSessionServiceFactory _createDeviceSessionService;

  LogTabController create({
    required String id,
    required String initialTitle,
    required LogTabSettings initialSettings,
    VoidCallback? onExitGetStarted,
    bool Function(String deviceId)? isDeviceSelectedInAnotherTab,
  }) {
    return LogTabController(
      id: id,
      initialTitle: initialTitle,
      initialSettings: initialSettings,
      onExitGetStarted: onExitGetStarted,
      isDeviceSelectedInAnotherTab: isDeviceSelectedInAnotherTab,
      deviceRepository: _deviceRepository,
      deviceSessionService: _createDeviceSessionService(),
    );
  }
}


