import 'package:flutter_test/flutter_test.dart';
import 'package:pura_air/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const PuraAirApp());
    expect(find.text('PURA AIR'), findsWidgets);
  });
}
