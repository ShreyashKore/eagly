import 'package:flutter/material.dart';

import '../../../data/device.dart';

IconData devicePlatformIcon(Device device) {
  return switch (device) {
    AndroidDevice() => Icons.android,
    IosDevice() => Icons.apple,
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
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary);
    final primaryStyle = _primaryTextStyle(theme);
    final secondaryStyle = _secondaryTextStyle(theme);

    final textColumn = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 6,
      children: [
        Text(
          label.primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: primaryStyle,
        ),
        if (label.secondary != null)
          Text(
            label.secondary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
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
          ? theme.colorScheme.onSurfaceVariant
          : baseStyle.color,
      decoration: device.isDisconnected
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );
  }

  TextStyle? _secondaryTextStyle(ThemeData theme) {
    final baseStyle = secondaryTextStyle ?? theme.textTheme.labelSmall;
    return baseStyle?.copyWith(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
      decoration: device.isDisconnected
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );
  }
}
