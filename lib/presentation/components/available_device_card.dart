import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_icon_button.dart';
import '../../data/device.dart';
import 'device_presentation.dart';
import 'layout_constants.dart';

class const AvailableDeviceCard({
  super.key,
  required this.device,
  required this.onSelected,
  this.onInstallApp,
  this.onShowMessage,
}) extends StatelessWidget {
  final Device device;
  final VoidCallback onSelected;
  final VoidCallback? onInstallApp;
  final ValueChanged<String>? onShowMessage;

  Future<void> _copyIosUdid() async {
    await Clipboard.setData(ClipboardData(text: device.id));
    onShowMessage?.call(LayoutConstants.iosUdidCopiedMessage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelected,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: DeviceLabel(
                  device: device,
                  textStyle: theme.textTheme.titleSmall,
                  showStatus: true,
                  iconColor: theme.colorScheme.primary,
                  iconSize: 20,
                ),
              ),
              switch (device) {
                IosDevice() => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconButton(
                      tooltip: 'Install app',
                      onPressed: onInstallApp,
                      icon: Icons.app_registration_outlined,
                    ),
                    AppIconButton(
                      tooltip: 'Copy UDID',
                      onPressed: _copyIosUdid,
                      icon: Icons.content_copy_outlined,
                    ),
                  ],
                ),
                AndroidDevice() => AppIconButton(
                  tooltip: 'Install app',
                  onPressed: onInstallApp,
                  icon: Icons.app_registration_outlined,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
