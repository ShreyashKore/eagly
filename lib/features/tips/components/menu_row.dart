import 'package:flutter/material.dart';

class const MenuRow(final IconData icon, final String label, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)],
    );
  }
}
