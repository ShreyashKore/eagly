import 'package:eagly/presentation/components/min_width_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget boxOfWidth(double width, TextEditingController text, FocusNode focus) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MinWidthBox(
              minWidth: 200,
              child: TextField(controller: text, focusNode: focus),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('keeps a focused field typing as the width crosses minWidth', (
    tester,
  ) async {
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(boxOfWidth(120, text, focus));
    focus.requestFocus();
    await tester.pump();
    final fieldState = tester.state(find.byType(EditableText));

    await tester.pumpWidget(boxOfWidth(320, text, focus));
    await tester.pumpWidget(boxOfWidth(120, text, focus));

    expect(tester.state(find.byType(EditableText)), same(fieldState));
    expect(tester.testTextInput.hasAnyClients, isTrue);
    tester.testTextInput.enterText('still typing');
    await tester.pump();
    expect(text.text, 'still typing');
  });

  testWidgets('gives the child the full width once there is room', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 20,
            child: MinWidthBox(minWidth: 200, child: SizedBox.expand()),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SizedBox).last).width, 320);
  });

  testWidgets('clips the child at minWidth when the space is narrower', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            height: 20,
            child: MinWidthBox(minWidth: 200, child: SizedBox.expand()),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SizedBox).last).width, 200);
    expect(tester.takeException(), isNull);
  });
}
