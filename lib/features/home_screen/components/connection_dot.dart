import 'package:flutter/material.dart';

class const ConnectionDot({super.key, required final bool connected})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected
            ? Colors.green
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
