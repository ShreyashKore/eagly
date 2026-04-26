import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/device.dart';
import '../device_presentation.dart';
import 'log_tab_view_constants.dart';

class AvailableDeviceCard extends StatelessWidget {
  const AvailableDeviceCard({
    super.key,
    required this.device,
    required this.onSelected,
    this.onShowMessage,
  });

  final Device device;
  final VoidCallback onSelected;
  final ValueChanged<String>? onShowMessage;

  Future<void> _copyIosUdid() async {
    await Clipboard.setData(ClipboardData(text: device.id));
    onShowMessage?.call(LogTabViewConstants.iosUdidCopiedMessage);
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
              if (device.isIos)
                IconButton(
                  tooltip: 'Copy UDID',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copyIosUdid,
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
