import 'package:flutter_test/flutter_test.dart';
import 'package:motoca_premium/app_shell.dart';

void main() {
  testWidgets('App inicia na tela de login', (WidgetTester tester) async {
    await tester.pumpWidget(const MotocaPremiumApp());
    await tester.pump();

    // Verifica que a tela de login aparece
    expect(find.text('Motoca Premium'), findsOneWidget);
    expect(find.text('Entrar'), findsWidgets);
  });
}
