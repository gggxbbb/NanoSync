import 'package:flutter_test/flutter_test.dart';
import 'package:nano_sync/main.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const NanoSyncApp());
    await tester.pumpAndSettle();
  });
}
