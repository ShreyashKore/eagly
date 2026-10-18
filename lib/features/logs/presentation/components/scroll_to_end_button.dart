import 'package:flutter/material.dart';

class const ScrollToEndButton({
  super.key,
  required final bool visible,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: visible
            ? FloatingActionButton(
                mini: true,
                onPressed: onPressed,
                tooltip: 'Scroll to End',
                child: const Icon(Icons.arrow_downward),
              )
            : SizedBox.shrink(),
      ),
    );
  }
}
