import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';

/// Thin vertical divider used to group toolbar buttons.
class const ToolbarDivider({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.scaled(18),
      child: VerticalDivider(
        width: 2,
        thickness: 2,
        radius: BorderRadius.circular(2),
      ),
    );
  }
}
