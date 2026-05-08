import 'package:flutter_test/flutter_test.dart';
import 'package:trax_app/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('TRAX'), findsOneWidget);
  });
}
