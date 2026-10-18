import 'package:flutter/material.dart';

import '../../../presentation/components/app_icon_button.dart';

class const HeaderAction({
  super.key,
  required final Object? icon,
  required final String tooltip,
  required final VoidCallback onPressed,
  final bool busy = false,
}) extends StatelessWidget {
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
