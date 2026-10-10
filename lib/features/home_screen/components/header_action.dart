import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';

class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final Object? icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return AppIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      busy: busy,
      iconSize: 20,
      icon: icon is IconData ? icon : null,
      child: icon is IconData
          ? null
          : icon is Widget
          ? icon
          : const SizedBox.shrink(),
    );
  }
}
