import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universa/main.dart';

void main() {
  testWidgets('UNIVERSA app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: UniversaApp()),
    );

    // Verify the app title renders
    expect(find.text('UNIVERSA'), findsOneWidget);
  });
}
