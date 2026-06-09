import 'package:flutter/material.dart';

import '../../data/device.dart';

IconData devicePlatformIcon(Device device) {
  return switch (device) {
    AndroidDevice() => Icons.android,
    IosDevice() => Icons.apple,
  };
}

/// Platform icon, with a subtle Wi-Fi badge for wireless Android devices.
class DevicePlatformIconWidget extends StatelessWidget {
  const DevicePlatformIconWidget({
    super.key,
    required this.device,
    required this.color,
    required this.size,
  });

  final Device device;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(devicePlatformIcon(device), color: color, size: size);
    final isWireless = device is AndroidDevice && (device as AndroidDevice).isWireless;
    if (!isWireless) return icon;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -3,
            bottom: -3,
            child: Icon(
              Icons.wifi,
              size: size * 0.48,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
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
            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
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
              color: device.isDisconnected
                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                  : null,
            ),
          ),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DevicePlatformIconWidget(
          device: device,
          color: effectiveIconColor,
          size: iconSize ?? 24,
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
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
          : baseStyle.color,
    );
  }
}

class DeviceSelectionLabel extends StatelessWidget {
  const DeviceSelectionLabel({
    super.key,
    required this.device,
    this.textStyle,
    this.secondaryTextStyle,
    this.iconColor,
    this.maxWidth,
    this.iconSize,
  });

  final Device device;
  final TextStyle? textStyle;
  final TextStyle? secondaryTextStyle;
  final Color? iconColor;
  final double? maxWidth;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = device.displayLabel;
    final effectiveIconColor =
        iconColor ??
        (device.isDisconnected
            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
            : theme.colorScheme.primary);
    final primaryStyle = _primaryTextStyle(theme);
    final secondaryStyle = _secondaryTextStyle(theme);

    final textColumn = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 6,
      children: [
        Flexible(
          child: Text(
            label.primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: primaryStyle,
          ),
        ),
        if (label.secondary != null)
          Flexible(
            child: Text(
              label.secondary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secondaryStyle,
            ),
          ),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DevicePlatformIconWidget(
          device: device,
          color: effectiveIconColor,
          size: iconSize ?? 24,
        ),
        const SizedBox(width: 8),
        if (maxWidth != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: textColumn,
          )
        else
          Flexible(child: textColumn),
      ],
    );
  }

  TextStyle? _primaryTextStyle(ThemeData theme) {
    final baseStyle = textStyle ?? theme.textTheme.bodySmall;
    return baseStyle?.copyWith(
      color: device.isDisconnected
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
          : baseStyle.color,
    );
  }

  TextStyle? _secondaryTextStyle(ThemeData theme) {
    final baseStyle = secondaryTextStyle ?? theme.textTheme.labelSmall;
    return baseStyle?.copyWith(
      fontSize: 10,
      color: device.isDisconnected
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
          : baseStyle.color,
    );
  }
}
