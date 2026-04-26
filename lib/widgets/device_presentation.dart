import 'package:flutter/material.dart';

import '../data/device.dart';

IconData devicePlatformIcon(Device device) {
  return switch (device.platform) {
    DevicePlatform.android => Icons.android,
    DevicePlatform.ios => Icons.apple,
  };
}

class DeviceLabel extends StatelessWidget {
  const DeviceLabel({
    super.key,
    required this.device,
    this.textStyle,
    this.iconColor,
    this.maxWidth,
    this.showStatus = false,
    this.iconSize,
  });

  final Device device;
  final TextStyle? textStyle;
  final Color? iconColor;
  final double? maxWidth;
  final bool showStatus;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTextStyle = _textStyle(theme);
    final effectiveIconColor =
        iconColor ??
        (device.isDisconnected
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary);

    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: effectiveTextStyle,
        ),
        if (showStatus)
          Text(
            '${device.id} · ${device.statusLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: device.isDisconnected
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          devicePlatformIcon(device),
          color: effectiveIconColor,
          size: iconSize,
        ),
        const SizedBox(width: 8),
        if (maxWidth != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: label,
          )
        else
          Flexible(child: label),
      ],
    );
  }

  TextStyle? _textStyle(ThemeData theme) {
    final baseStyle = textStyle ?? theme.textTheme.bodyMedium;
    return baseStyle?.copyWith(
      color: device.isDisconnected
          ? theme.colorScheme.onSurfaceVariant
          : baseStyle.color,
      decoration: device.isDisconnected
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );
  }
}
