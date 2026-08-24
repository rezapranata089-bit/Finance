import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/main.dart';

void main() {
  testWidgets('My Finance opens dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const MyFinanceApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Selamat pagi, Raka'), findsOneWidget);
    expect(find.text('TOTAL SALDO'), findsOneWidget);
    expect(find.text('Aksi cepat'), findsOneWidget);
  });
}