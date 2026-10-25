import 'package:eagly/presentation/components/hover_builder.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rebuilds with the hover state as the pointer enters and leaves',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: HoverBuilder(
              builder: (context, hovered) => SizedBox.square(
                dimension: 50,
                child: Text(hovered ? 'over' : 'out'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('out'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(SizedBox).last));
      await tester.pump();
      expect(find.text('over'), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.text('out'), findsOneWidget);
    },
  );
}
