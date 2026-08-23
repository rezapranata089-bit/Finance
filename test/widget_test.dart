import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_finance/main.dart';

void main() {
  testWidgets('My Finance opens dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyFinanceApp()));
    await tester.pumpAndSettle();

    expect(find.text('Selamat pagi, Raka'), findsOneWidget);
    expect(find.text('SALDO TERKINI'), findsOneWidget);
  });
}