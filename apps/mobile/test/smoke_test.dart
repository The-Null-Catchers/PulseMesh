import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/main.dart';

void main() {
  testWidgets('PulseMesh renders the workspace shell', (tester) async {
    await tester.pumpWidget(const PulseMeshApp());
    await tester.pumpAndSettle();

    expect(find.text('The Null Catchers'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);
  });
}
