import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ZawerJewelleryApp());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ZawerJewelleryApp), findsOneWidget);
  });
}