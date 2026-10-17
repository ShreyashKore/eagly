import 'package:flutter/material.dart';

/// A fixed-width header label cell for the log viewer's column header row.
class const HeaderCell({
  super.key,
  required final String text,
  required final double width,
  required final TextStyle style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
