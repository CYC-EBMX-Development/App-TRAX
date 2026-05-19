import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/common/widgets/trax_button.dart';

void main() {
  group('TraxButton', () {
    testWidgets('renders provided text and triggers onPressed', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TraxButton.filled(
              text: 'Go',
              onPressed: () => tapped++,
            ),
          ),
        ),
      ));

      expect(find.text('Go'), findsOneWidget);
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(tapped, 1);
    });

    testWidgets('text factory renders given child when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TraxButton.text(
            child: const Icon(Icons.add, key: ValueKey('plus')),
            onPressed: () {},
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('plus')), findsOneWidget);
    });

    testWidgets('outlined variant respects onPressed null disables button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TraxButton.outlined(text: 'Disabled', onPressed: null),
        ),
      ));

      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNull);
    });
  });

  group('TraxReturnButton', () {
    testWidgets('renders back arrow icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TraxReturnButton(onPressed: () {})),
      ));
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });
  });
}
