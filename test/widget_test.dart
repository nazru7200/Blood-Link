import 'package:flutter_test/flutter_test.dart';
import 'package:blood_link/main.dart';

void main() {
  testWidgets('Blood Link app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const BloodLinkApp());

    expect(find.text('Blood Link'), findsOneWidget);
  });
}