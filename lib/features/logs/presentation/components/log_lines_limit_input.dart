import 'package:flutter/material.dart';

import '../../../../presentation/components/app_icon_button.dart';

class const LogLinesLimitInput({
  super.key,
  required this.setEditingLogLinesLimit,
  required this.submitLogLinesLimit,
  required this.logLinesLimit,
  required this.isEditing,
}) extends StatefulWidget {
  final void Function(bool) setEditingLogLinesLimit;
  final Function(int) submitLogLinesLimit;
  final int logLinesLimit;
  final bool isEditing;

  @override
  State<LogLinesLimitInput> createState() => _LogLinesLimitInputState();
}

class _LogLinesLimitInputState extends State<LogLinesLimitInput> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.logLinesLimit.toString());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LogLinesLimitInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      controller.text = widget.logLinesLimit.toString();
    }
    if (widget.logLinesLimit != oldWidget.logLinesLimit) {
      controller.text = widget.logLinesLimit.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      onTapOutside: (_) => widget.setEditingLogLinesLimit(false),
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        prefixText: 'Max lines: ',
        border: const OutlineInputBorder(),
        suffix: AppIconButton(
          tooltip: 'Apply',
          iconSize: 14,
          padding: 2,
          onPressed: () => widget.submitLogLinesLimit(
            int.tryParse(controller.text) ?? widget.logLinesLimit,
          ),
          icon: Icons.check,
        ),
      ),
      onSubmitted: (value) => widget.submitLogLinesLimit(
        int.tryParse(value) ?? widget.logLinesLimit,
      ),
      onEditingComplete: () => widget.setEditingLogLinesLimit(false),
    );
  }
}
