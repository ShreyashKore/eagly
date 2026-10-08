import 'package:flutter/material.dart';

import '../../data/device.dart';

IconData devicePlatformIcon(Device device) {
  return switch (device) {
    AndroidDevice() => Icons.android,
    IosDevice() => Icons.apple,
  };
}

/// Platform icon, with a subtle Wi-Fi badge for wireless Android devices.
class const DevicePlatformIconWidget({
  super.key,
  required final Device device,
  required final Color color,
  required final double size,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final icon = Icon(devicePlatformIcon(device), color: color, size: size);
    if (!device.isWireless) return icon;

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

class const DeviceLabel({
  super.key,
  required final Device device,
  final TextStyle? textStyle,
  final Color? iconColor,
  final double? maxWidth,
  final bool showStatus = false,
  final double? iconSize,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTextStyle = _textStyle(theme);

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
            '${device.shownId} · ${device.statusLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: device.isDisconnected ? _dimmed(theme) : null,
            ),
          ),
      ],
    );

    return _IconLabelRow(
      device: device,
      iconColor: iconColor,
      iconSize: iconSize,
      maxWidth: maxWidth,
      label: label,
    );
  }

  TextStyle? _textStyle(ThemeData theme) {
    final baseStyle = textStyle ?? theme.textTheme.bodyMedium;
    return baseStyle?.copyWith(
      color: device.isDisconnected ? _dimmed(theme) : baseStyle.color,
    );
  }
}

class const DeviceSelectionLabel({
  super.key,
  required final Device device,
  final TextStyle? textStyle,
  final TextStyle? secondaryTextStyle,
  final Color? iconColor,
  final double? maxWidth,
  final double? iconSize,

  /// Whether to show the label's secondary part (see [Device.displayLabel]).
  final bool showSecondary = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = device.displayLabel;
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
        if (showSecondary && label.secondary != null)
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

    return _IconLabelRow(
      device: device,
      iconColor: iconColor,
      iconSize: iconSize,
      maxWidth: maxWidth,
      label: textColumn,
    );
  }

  TextStyle? _primaryTextStyle(ThemeData theme) {
    final baseStyle = textStyle ?? theme.textTheme.bodySmall;
    return baseStyle?.copyWith(
      color: device.isDisconnected ? _dimmed(theme) : baseStyle.color,
    );
  }

  TextStyle? _secondaryTextStyle(ThemeData theme) {
    final baseStyle = secondaryTextStyle ?? theme.textTheme.labelSmall;
    return baseStyle?.copyWith(
      fontSize: 10,
      color: device.isDisconnected ? _dimmed(theme) : baseStyle.color,
    );
  }
}

/// Text and icons of a disconnected device.
Color _dimmed(ThemeData theme) =>
    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

/// [device]'s platform icon, then [label] — capped at [maxWidth] when given.
class const _IconLabelRow({
  required final Device device,
  required final Color? iconColor,
  required final double? iconSize,
  required final double? maxWidth,
  required final Widget label,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DevicePlatformIconWidget(
          device: device,
          color:
              iconColor ??
              (device.isDisconnected
                  ? _dimmed(theme)
                  : theme.colorScheme.primary),
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
}
