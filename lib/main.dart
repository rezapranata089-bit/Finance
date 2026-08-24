import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const MyFinanceApp(),
  ));
}

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
class AppThemePalette {
  final String name;
  final Color primary, secondary, tertiary;
  const AppThemePalette(this.name, this.primary, this.secondary, this.tertiary);
}

const appPalettes = [
  AppThemePalette('Lavender Glow', Color(0xFF7655D8), Color(0xFFD6F6A6), Color(0xFFF4EDFF)),
  AppThemePalette('Emerald City', Color(0xFF24A148), Color(0xFFD6F6A6), Color(0xFFE7F7EA)),
  AppThemePalette('Rose Petal', Color(0xFFE05270), Color(0xFFFFD8E4), Color(0xFFFBE8ED)),
  AppThemePalette('Ocean Breeze', Color(0xFF2196F3), Color(0xFFFFC107), Color(0xFFE3F2FD)),
  AppThemePalette('Sunset Vibes', Color(0xFFFF9800), Color(0xFF4CAF50), Color(0xFFFFF3E0)),
];

final tabProvider = StateProvider<int>((ref) => 0);
final onboardingProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('onboarding_done') ?? false);
final themeProvider = StateProvider<AppThemePalette>((ref) => appPalettes[0]);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

enum AppLang { en, id }

final langProvider = StateProvider<AppLang>((ref) {
  final saved = ref.watch(prefsProvider).getString('app_lang');
  return saved == 'id' ? AppLang.id : AppLang.en;
});

extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get cardColor => isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
  Color get borderColor => isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF25212E);
  Color get textMuted => isDark ? Colors.white60 : Colors.grey.shade600;
  Color get textFaint => isDark ? Colors.white38 : Colors.grey.shade500;
  Color get iconMuted => isDark ? Colors.white54 : Colors.grey;
}

class Strings {
  static const Map<String, Map<AppLang, String>> _s = {
    'skip': {AppLang.en: 'Skip', AppLang.id: 'Lewati'},
    'onboarding_title_1': {AppLang.en: 'Manage your finances\nmore easily', AppLang.id: 'Kelola keuanganmu\nlebih mudah'},
    'onboarding_desc_1': {AppLang.en: 'Track income, expenses, and monitor your balance growth.', AppLang.id: 'Catat pemasukan, pengeluaran, dan pantau perkembangan saldo.'},
    'onboarding_title_2': {AppLang.en: 'All transactions\nin one place', AppLang.id: 'Semua transaksi\ndalam satu tempat'},
    'onboarding_desc_2': {AppLang.en: 'Keep track of your financial activity in a neater, simpler way.', AppLang.id: 'Pantau aktivitas keuangan dengan cara yang lebih rapi dan sederhana.'},
    'onboarding_title_3': {AppLang.en: 'Understand your finances', AppLang.id: 'Pahami keuanganmu'},
    'onboarding_desc_3': {AppLang.en: 'View reports to make better financial decisions.', AppLang.id: 'Lihat laporan untuk mengambil keputusan finansial yang lebih baik.'},
    'get_started': {AppLang.en: 'Get started', AppLang.id: 'Mulai sekarang'},
    'continue': {AppLang.en: 'Continue', AppLang.id: 'Lanjutkan'},
    'nav_home': {AppLang.en: 'Home', AppLang.id: 'Beranda'},
    'nav_statistic': {AppLang.en: 'Statistic', AppLang.id: 'Statistik'},
    'nav_card': {AppLang.en: 'Card', AppLang.id: 'Kartu'},
    'nav_profile': {AppLang.en: 'Profile', AppLang.id: 'Profil'},
    'my_account': {AppLang.en: 'My Account', AppLang.id: 'Akun Saya'},
    'your_balance': {AppLang.en: 'Your Balance', AppLang.id: 'Saldo Anda'},
    'saved_last_month': {AppLang.en: 'You saved {amount} last month', AppLang.id: 'Anda menghemat {amount} bulan lalu'},
    'send': {AppLang.en: 'Send', AppLang.id: 'Kirim'},
    'request': {AppLang.en: 'Request', AppLang.id: 'Minta'},
    'exchange': {AppLang.en: 'Exchange', AppLang.id: 'Tukar'},
    'more': {AppLang.en: 'More', AppLang.id: 'Lainnya'},
    'top_merchants': {AppLang.en: 'Top Merchants', AppLang.id: 'Merchant Teratas'},
    'view_all': {AppLang.en: 'View all', AppLang.id: 'Lihat semua'},
    'discount_title': {AppLang.en: 'Discount Up To 80%', AppLang.id: 'Diskon Hingga 80%'},
    'discount_subtitle': {AppLang.en: 'Festive Season Gift', AppLang.id: 'Hadiah Musim Perayaan'},
    'transaction_history': {AppLang.en: 'Transaction History', AppLang.id: 'Riwayat Transaksi'},
    'today': {AppLang.en: 'TODAY', AppLang.id: 'HARI INI'},
    'receive': {AppLang.en: 'Receive', AppLang.id: 'Terima'},
    'transfer': {AppLang.en: 'Transfer', AppLang.id: 'Transfer'},
    'transactions_title': {AppLang.en: 'Transactions', AppLang.id: 'Transaksi'},
    'transactions_subtitle': {AppLang.en: 'All your financial activity', AppLang.id: 'Semua aktivitas keuanganmu'},
    'search_transactions': {AppLang.en: 'Search transactions', AppLang.id: 'Cari transaksi'},
    'filter_all': {AppLang.en: 'All', AppLang.id: 'Semua'},
    'filter_income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'filter_expense': {AppLang.en: 'Expense', AppLang.id: 'Pengeluaran'},
    'reports_title': {AppLang.en: 'Reports', AppLang.id: 'Laporan'},
    'cash_flow': {AppLang.en: 'Cash flow this month', AppLang.id: 'Arus kas bulan ini'},
    'expense_by_category': {AppLang.en: 'Expenses by category', AppLang.id: 'Pengeluaran berdasarkan kategori'},
    'income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'expense': {AppLang.en: 'Expense', AppLang.id: 'Pengeluaran'},
    'savings': {AppLang.en: 'Savings', AppLang.id: 'Tabungan'},
    'profile_title': {AppLang.en: 'Profile', AppLang.id: 'Profil'},
    'manage_account': {AppLang.en: 'Manage your finance account', AppLang.id: 'Kelola akun keuanganmu'},
    'section_finance': {AppLang.en: 'Finance', AppLang.id: 'Keuangan'},
    'savings_target': {AppLang.en: 'Savings target', AppLang.id: 'Target tabungan'},
    'category': {AppLang.en: 'Category', AppLang.id: 'Kategori'},
    'account_wallet': {AppLang.en: 'Account / Wallet', AppLang.id: 'Akun / Dompet'},
    'receivables': {AppLang.en: 'Receivables', AppLang.id: 'Piutang'},
    'section_app': {AppLang.en: 'App', AppLang.id: 'Aplikasi'},
    'appearance': {AppLang.en: 'Appearance', AppLang.id: 'Tampilan'},
    'language': {AppLang.en: 'Language', AppLang.id: 'Bahasa'},
    'notifications': {AppLang.en: 'Notifications', AppLang.id: 'Notifikasi'},
    'backup_data': {AppLang.en: 'Backup data', AppLang.id: 'Backup data'},
    'not_available': {AppLang.en: '{name} is not available yet', AppLang.id: '{name} belum tersedia'},
    'screen_mode': {AppLang.en: 'SCREEN MODE', AppLang.id: 'MODE LAYAR'},
    'light': {AppLang.en: 'Light', AppLang.id: 'Terang'},
    'dark': {AppLang.en: 'Dark', AppLang.id: 'Gelap'},
    'system': {AppLang.en: 'System', AppLang.id: 'Sistem'},
    'theme_color': {AppLang.en: 'THEME COLOR', AppLang.id: 'WARNA TEMA'},
    'add_income': {AppLang.en: 'Add income', AppLang.id: 'Tambah pemasukan'},
    'add_expense': {AppLang.en: 'Add expense', AppLang.id: 'Tambah pengeluaran'},
    'amount': {AppLang.en: 'Amount', AppLang.id: 'Nominal'},
    'transaction_title_field': {AppLang.en: 'Transaction title', AppLang.id: 'Judul transaksi'},
    'note_optional': {AppLang.en: 'Note (optional)', AppLang.id: 'Catatan (opsional)'},
    'save_transaction': {AppLang.en: 'Save transaction', AppLang.id: 'Simpan transaksi'},
    'cat_income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'cat_freelance': {AppLang.en: 'Freelance', AppLang.id: 'Freelance'},
    'cat_bonus': {AppLang.en: 'Bonus', AppLang.id: 'Bonus'},
    'cat_food': {AppLang.en: 'Food', AppLang.id: 'Makanan'},
    'cat_shopping': {AppLang.en: 'Shopping', AppLang.id: 'Belanja'},
    'cat_transport': {AppLang.en: 'Transport', AppLang.id: 'Transport'},
    'cat_bills': {AppLang.en: 'Bills', AppLang.id: 'Tagihan'},
    'cat_other': {AppLang.en: 'Other', AppLang.id: 'Lainnya'},
  };

  static String t(AppLang lang, String key) => _s[key]?[lang] ?? key;
}

class FinanceTransaction {
  final String title, category, note;
  final double amount;
  final bool income;
  final DateTime date;
  const FinanceTransaction({
    required this.title,
    required this.category,
    required this.note,
    required this.amount,
    required this.income,
    required this.date,
  });
}

final transactionsProvider = StateNotifierProvider<TransactionNotifier, List<FinanceTransaction>>(
  (ref) => TransactionNotifier(),
);

class TransactionNotifier extends StateNotifier<List<FinanceTransaction>> {
  TransactionNotifier()
      : super([
          FinanceTransaction(title: 'Monthly Salary', category: 'Income', note: 'August salary', amount: 8500000, income: true, date: DateTime(2026, 8, 24, 8, 30)),
          FinanceTransaction(title: 'Grocery shopping', category: 'Shopping', note: 'Household needs', amount: 250000, income: false, date: DateTime(2026, 8, 24, 12, 30)),
          FinanceTransaction(title: 'Afternoon coffee', category: 'Food', note: '', amount: 25000, income: false, date: DateTime(2026, 8, 24, 15, 20)),
          FinanceTransaction(title: 'Freelance design', category: 'Income', note: '', amount: 500000, income: true, date: DateTime(2026, 8, 23, 10, 0)),
          FinanceTransaction(title: 'Transportation', category: 'Transport', note: '', amount: 120000, income: false, date: DateTime(2026, 8, 23, 8, 15)),
          FinanceTransaction(title: 'Internet bill', category: 'Bills', note: '', amount: 350000, income: false, date: DateTime(2026, 8, 20)),
        ]);

  void add({required String title, required double amount, required bool income, required String category, required String note, required DateTime date}) {
    state = [FinanceTransaction(title: title, amount: amount, income: income, category: category, note: note, date: date), ...state];
  }
}

class MyFinanceApp extends ConsumerWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingProvider);
    final theme = ref.watch(themeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primary,
          primary: theme.primary,
          secondary: theme.secondary,
          tertiary: theme.tertiary,
          brightness: Brightness.light,
        ),
        fontFamily: 'Satoshi',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1B27),
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: theme.primary,
          secondary: theme.secondary,
          tertiary: theme.tertiary,
          surface: const Color(0xFF121016),
          onSurface: Colors.white,
        ),
        fontFamily: 'Satoshi',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        iconTheme: const IconThemeData(color: Colors.white),
        textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF1E1B27),
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      home: seen ? const FinanceShell() : const OnboardingPage(),
    );
  }
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int page = 0;
  final slideKeys = const [
    ('onboarding_title_1', 'onboarding_desc_1'),
    ('onboarding_title_2', 'onboarding_desc_2'),
    ('onboarding_title_3', 'onboarding_desc_3'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final last = page == slideKeys.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('MY FINANCE', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w900, letterSpacing: 2)),
              TextButton(onPressed: () => _finish(), child: Text(Strings.t(lang, 'skip'))),
            ]),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 330, width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? colors.primary.withOpacity(0.16) : colors.tertiary, borderRadius: BorderRadius.circular(40),
                  ),
                  child: Stack(children: [
                    Positioned(top: 42, left: 28, child: _orb(colors.primary.withOpacity(0.4), 54)),
                    Positioned(top: 88, right: 40, child: _orb(colors.primary.withOpacity(0.7), 90)),
                    Positioned(bottom: 44, left: 80, child: _orb(colors.primary, 120)),
                    Center(child: Icon(last ? SolarIconsBold.chart : page == 1 ? SolarIconsBold.billList : SolarIconsBold.wallet, size: 94, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 40),
                Text(Strings.t(lang, slideKeys[page].$1), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 36, height: 1.08, color: context.textPrimary)),
                const SizedBox(height: 16),
                Text(Strings.t(lang, slideKeys[page].$2), style: TextStyle(fontSize: 16, height: 1.5, color: context.textMuted)),
              ]),
            ),
            Row(children: [
              ...List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 220), margin: const EdgeInsets.only(right: 6), width: i == page ? 28 : 7, height: 7, decoration: BoxDecoration(color: i == page ? colors.primary : (isDark ? Colors.white24 : colors.tertiary), borderRadius: BorderRadius.circular(20)))),
              const Spacer(),
              FilledButton.icon(onPressed: () => last ? _finish() : setState(() => page++), icon: Icon(last ? Icons.check : SolarIconsOutline.arrowRight), label: Text(last ? Strings.t(lang, 'get_started') : Strings.t(lang, 'continue'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _orb(Color color, double size) => Container(width: size, height: size, decoration: BoxDecoration(color: color.withOpacity(.8), shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(.25), blurRadius: 22)]));
  void _finish() {
    ref.read(prefsProvider).setBool('onboarding_done', true);
    ref.read(onboardingProvider.notifier).state = true;
  }
}

class FinanceShell extends ConsumerWidget {
  const FinanceShell({super.key});
  static const pages = [HomePage(), ReportsPage(), TransactionsPage(), ProfilePage()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final lang = ref.watch(langProvider);
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(context, 0, SolarIconsOutline.home, SolarIconsBold.home, Strings.t(lang, 'nav_home'), tab, ref),
            _navItem(context, 1, SolarIconsOutline.chart, SolarIconsBold.chart, Strings.t(lang, 'nav_statistic'), tab, ref),
            GestureDetector(
              onTap: () {},
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(SolarIconsOutline.scanner, color: Colors.black),
              ),
            ),
            _navItem(context, 2, SolarIconsOutline.card, SolarIconsBold.card, Strings.t(lang, 'nav_card'), tab, ref),
            _navItem(context, 3, SolarIconsOutline.user, SolarIconsBold.user, Strings.t(lang, 'nav_profile'), tab, ref),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int index, IconData iconOutline, IconData iconBold, String label, int currentTab, WidgetRef ref) {
    final isSelected = currentTab == index;
    return GestureDetector(
      onTap: () => ref.read(tabProvider.notifier).state = index,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSelected ? iconBold : iconOutline, color: isSelected ? context.textPrimary : context.iconMuted, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: isSelected ? context.textPrimary : context.iconMuted, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final balance = 50000000 + income - expense;
    final primary = Theme.of(context).colorScheme.primary;
    final accent = Theme.of(context).colorScheme.secondary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final isDark = context.isDark;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: BoxDecoration(
              color: Color.alphaBlend(primary.withOpacity(isDark ? 0.12 : 0.05), context.cardColor),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.20) : Colors.black.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.22) : Colors.black.withOpacity(0.06),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: context.cardColor, shape: BoxShape.circle, border: Border.all(color: context.borderColor)),
                      child: Icon(SolarIconsOutline.hamburgerMenu, size: 20, color: context.textPrimary),
                    ),
                    Text(Strings.t(lang, 'my_account'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary)),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: context.cardColor, shape: BoxShape.circle, border: Border.all(color: context.borderColor)),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(SolarIconsOutline.bell, size: 20, color: context.textPrimary),
                          Positioned(
                            right: -2, top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                              child: const Text('2', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.borderColor)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20, height: 14,
                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 8),
                        Text('**** 3425', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
                        const SizedBox(width: 4),
                        Icon(SolarIconsOutline.altArrowDown, size: 16, color: context.iconMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(child: Text(Strings.t(lang, 'your_balance'), style: TextStyle(color: context.textMuted, fontSize: 13, fontWeight: FontWeight.w500))),
                const SizedBox(height: 8),
                Center(child: Text(rupiah(balance), style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1, color: context.textPrimary))),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: primary.withOpacity(isDark ? 0.18 : 0.08), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(SolarIconsBold.stars, size: 14, color: primary),
                        const SizedBox(width: 6),
                        Text('${Strings.t(lang, 'saved_last_month').replaceAll('{amount}', rupiah(290000))} >', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _actionBtn(context, SolarIconsOutline.arrowRightUp, Strings.t(lang, 'send'), primaryStyle: true, onTap: () => showTransactionForm(context, ref, false)),
                    _actionBtn(context, SolarIconsOutline.arrowLeftDown, Strings.t(lang, 'request'), primaryStyle: false, onTap: () => showTransactionForm(context, ref, true)),
                    _actionBtn(context, SolarIconsOutline.transferHorizontal, Strings.t(lang, 'exchange'), primaryStyle: false, onTap: () => ref.read(tabProvider.notifier).state = 2),
                    _actionBtn(context, SolarIconsOutline.menuDots, Strings.t(lang, 'more'), primaryStyle: false, onTap: () => ref.read(tabProvider.notifier).state = 3),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Strings.t(lang, 'top_merchants'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                    Text('${Strings.t(lang, 'view_all')} >', style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Strings.t(lang, 'discount_title'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                            const SizedBox(height: 4),
                            Text(Strings.t(lang, 'discount_subtitle'), style: TextStyle(color: context.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                        child: Icon(SolarIconsBold.bag2, color: primary, size: 24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Strings.t(lang, 'transaction_history'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                    Text('${Strings.t(lang, 'view_all')} >', style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(Strings.t(lang, 'today'), style: TextStyle(color: context.textFaint, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                ...items.take(4).map((item) => TransactionTile(item: item)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, {required bool primaryStyle, required VoidCallback onTap}) {
    final accent = Theme.of(context).colorScheme.secondary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 68,
            height: 48,
            decoration: BoxDecoration(
              color: primaryStyle ? accent : context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: primaryStyle ? null : Border.all(color: context.borderColor),
            ),
            child: Icon(icon, color: primaryStyle ? Colors.black : context.textPrimary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
        ],
      ),
    );
  }
}

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});
  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}
class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  String query = '';
  String filter = 'all';
  static const filterKeys = ['all', 'income', 'expense'];
  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final items = all.where((e) => (filter == 'all' || (filter == 'income' ? e.income : !e.income)) && e.title.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      Text(Strings.t(lang, 'transactions_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
      Text(Strings.t(lang, 'transactions_subtitle'), style: TextStyle(color: context.textMuted)),
      const SizedBox(height: 22),
      TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(hintText: Strings.t(lang, 'search_transactions'), prefixIcon: const Icon(Icons.search))),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filterKeys
              .map<Widget>(
                (k) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(Strings.t(lang, 'filter_$k')),
                    selected: filter == k,
                    onSelected: (_) => setState(() => filter = k),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 20),
      ...items.map((item) => TransactionTile(item: item)),
    ]));
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final groups = <String, double>{};
    for (final item in items.where((e) => !e.income)) groups[item.category] = (groups[item.category] ?? 0) + item.amount;
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      Text(Strings.t(lang, 'reports_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
      Text(DateFormat('MMMM yyyy', lang == AppLang.id ? 'id_ID' : 'en_US').format(DateTime(2026, 8, 24)), style: TextStyle(color: context.textMuted)),
      const SizedBox(height: 22),
      SummaryCard(income: income, expense: expense),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'cash_flow')),
      const SizedBox(height: 12),
      Container(height: 190, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)), child: CustomPaint(painter: SimpleChartPainter(primary: Theme.of(context).colorScheme.primary, gridColor: context.isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEDEAF2)))),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'expense_by_category')),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)), child: Column(children: groups.entries.map((e) => ReportRow(label: e.key, amount: e.value, total: expense)).toList())),
    ]));
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      Text(Strings.t(lang, 'profile_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)),
        child: Row(children: [
          CircleAvatar(radius: 31, backgroundColor: Theme.of(context).colorScheme.primary, child: const Text('R', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold))),
          const SizedBox(width: 15),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Raka', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
            const SizedBox(height: 4),
            Text(Strings.t(lang, 'manage_account'), style: TextStyle(color: context.textMuted)),
          ]),
        ]),
      ),
      const SizedBox(height: 26),
      SectionTitle(Strings.t(lang, 'section_finance')),
      const SizedBox(height: 10),
      SettingList(items: const [
        ('savings_target', SolarIconsOutline.safeSquare),
        ('category', SolarIconsOutline.widget),
        ('account_wallet', SolarIconsOutline.wallet),
        ('receivables', SolarIconsOutline.usersGroupTwoRounded),
      ]),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'section_app')),
      const SizedBox(height: 10),
      SettingList(items: const [
        ('appearance', SolarIconsOutline.palette),
        ('language', Icons.language),
        ('notifications', SolarIconsOutline.bell),
        ('backup_data', SolarIconsOutline.cloudUpload),
      ]),
    ]));
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.textPrimary));
}

class TransactionTile extends ConsumerWidget {
  final FinanceTransaction item;
  const TransactionTile({super.key, required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: context.isDark ? primary.withOpacity(0.18) : Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle),
            child: Center(
              child: Text(
                item.title.substring(0, 1).toUpperCase(),
                style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.textPrimary)),
                const SizedBox(height: 4),
                Text(DateFormat('hh:mm a').format(item.date), style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.income ? '+' : '-'}${rupiah(item.amount)}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: context.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(Strings.t(lang, item.income ? 'receive' : 'transfer'), style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends ConsumerWidget {
  final double income, expense;
  const SummaryCard({super.key, required this.income, required this.expense});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)), child: Row(children: [
      Expanded(child: _summary(context, Strings.t(lang, 'income'), rupiah(income), const Color(0xFF24A148))),
      Container(width: 1, height: 44, color: context.borderColor),
      Expanded(child: _summary(context, Strings.t(lang, 'expense'), rupiah(expense), const Color(0xFFE05270))),
      Container(width: 1, height: 44, color: context.borderColor),
      Expanded(child: _summary(context, Strings.t(lang, 'savings'), '${((income - expense) / (income == 0 ? 1 : income) * 100).round()}%', Theme.of(context).colorScheme.primary)),
    ]));
  }
  Widget _summary(BuildContext context, String title, String value, Color color) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: context.textMuted, fontSize: 11)), const SizedBox(height: 7), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))]));
}

class ReportRow extends StatelessWidget {
  final String label; final double amount, total;
  const ReportRow({super.key, required this.label, required this.amount, required this.total});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary)), Text('${rupiah(amount)} · ${(amount / total * 100).round()}%', style: TextStyle(color: context.textMuted, fontSize: 12))]), const SizedBox(height: 8), LinearProgressIndicator(value: amount / total, minHeight: 7, borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.primary, backgroundColor: context.isDark ? Theme.of(context).colorScheme.primary.withOpacity(0.16) : Theme.of(context).colorScheme.tertiary)]));
}

class SettingList extends ConsumerWidget {
  final List<(String, IconData)> items;
  const SettingList({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: items
            .map<Widget>(
              (item) {
                final label = Strings.t(lang, item.$1);
                return ListTile(
                  onTap: () {
                    if (item.$1 == 'appearance') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionPage()));
                    } else if (item.$1 == 'language') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionPage()));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'not_available').replaceAll('{name}', label))));
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.$2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(label, style: TextStyle(color: context.textPrimary)),
                  trailing: Icon(SolarIconsOutline.altArrowRight, size: 20, color: context.iconMuted),
                );
              },
            )
            .toList(),
      ),
    );
  }
}

class ThemeSelectionPage extends ConsumerWidget {
  const ThemeSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeProvider);
    final currentMode = ref.watch(themeModeProvider);
    final lang = ref.watch(langProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
    final cardBg = isDark ? const Color(0xFF1E1B27) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                      ),
                      child: const Icon(SolarIconsOutline.arrowLeft, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(Strings.t(lang, 'appearance'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Text(Strings.t(lang, 'screen_mode'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        _modeBtn(context, ref, Strings.t(lang, 'light'), SolarIconsOutline.sun, ThemeMode.light, currentMode),
                        _modeBtn(context, ref, Strings.t(lang, 'dark'), SolarIconsOutline.moon, ThemeMode.dark, currentMode),
                        _modeBtn(context, ref, Strings.t(lang, 'system'), SolarIconsOutline.monitor, ThemeMode.system, currentMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(Strings.t(lang, 'theme_color'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Column(
                      children: appPalettes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final palette = entry.value;
                        final isSelected = currentTheme.name == palette.name;
                        
                        return Column(
                          children: [
                            ListTile(
                              onTap: () => ref.read(themeProvider.notifier).state = palette,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 0.5),
                                  gradient: SweepGradient(
                                    colors: [
                                      palette.primary, palette.primary,
                                      palette.secondary, palette.secondary,
                                      palette.tertiary, palette.tertiary
                                    ],
                                    stops: const [0.0, 0.33, 0.33, 0.66, 0.66, 1.0],
                                  ),
                                ),
                              ),
                              title: Text(palette.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              trailing: isSelected 
                                  ? Icon(SolarIconsBold.checkCircle, color: palette.primary, size: 28)
                                  : Icon(SolarIconsOutline.roundAltArrowRight, color: context.iconMuted, size: 24),
                            ),
                            if (index != appPalettes.length - 1)
                              Divider(height: 1, indent: 80, endIndent: 20, color: isDark ? Colors.white12 : Colors.grey.shade100),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(BuildContext context, WidgetRef ref, String title, IconData icon, ThemeMode mode, ThemeMode currentMode) {
    final isSelected = currentMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(themeModeProvider.notifier).state = mode,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? Colors.white12 : primary.withOpacity(0.08)) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? primary : context.iconMuted, size: 24),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? primary : context.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageSelectionPage extends ConsumerWidget {
  const LanguageSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final cardBg = context.cardColor;
    final primary = Theme.of(context).colorScheme.primary;
    final options = [
      (AppLang.en, 'English', 'EN'),
      (AppLang.id, 'Bahasa Indonesia', 'ID'),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: cardBg, shape: BoxShape.circle, border: Border.all(color: context.borderColor)),
                      child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: context.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(Strings.t(lang, 'language'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Container(
                    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)),
                    child: Column(
                      children: options.asMap().entries.map((entry) {
                        final i = entry.key;
                        final opt = entry.value;
                        final selected = lang == opt.$1;
                        return Column(children: [
                          ListTile(
                            onTap: () {
                              ref.read(langProvider.notifier).state = opt.$1;
                              ref.read(prefsProvider).setString('app_lang', opt.$1 == AppLang.id ? 'id' : 'en');
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            leading: CircleAvatar(radius: 20, backgroundColor: primary.withOpacity(isDark ? 0.22 : 0.1), child: Text(opt.$3, style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 12))),
                            title: Text(opt.$2, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: context.textPrimary)),
                            trailing: selected
                                ? Icon(SolarIconsBold.checkCircle, color: primary, size: 26)
                                : Icon(SolarIconsOutline.roundAltArrowRight, color: context.iconMuted, size: 22),
                          ),
                          if (i != options.length - 1) Divider(height: 1, indent: 76, endIndent: 20, color: context.borderColor),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleChartPainter extends CustomPainter {
  final Color primary;
  final Color gridColor;
  SimpleChartPainter({required this.primary, required this.gridColor});
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = gridColor..strokeWidth = 1;
    for (var i = 1; i < 5; i++) canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5), grid);
    final line = Paint()..color = primary..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height * .72)..cubicTo(size.width * .16, size.height * .50, size.width * .2, size.height * .62, size.width * .35, size.height * .48)..cubicTo(size.width * .5, size.height * .32, size.width * .62, size.height * .6, size.width * .76, size.height * .28)..cubicTo(size.width * .84, size.height * .18, size.width * .92, size.height * .35, size.width, size.height * .15);
    canvas.drawPath(path, line);
  }
  @override
  bool shouldRepaint(covariant SimpleChartPainter oldDelegate) => oldDelegate.primary != primary || oldDelegate.gridColor != gridColor;
}

Future<void> showTransactionForm(BuildContext context, WidgetRef ref, bool income) async {
  final amount = TextEditingController(), title = TextEditingController(), note = TextEditingController();
  final lang = ref.read(langProvider);
  final catKeys = income
      ? ['cat_income', 'cat_freelance', 'cat_bonus']
      : ['cat_food', 'cat_shopping', 'cat_transport', 'cat_bills', 'cat_other'];
  String category = Strings.t(AppLang.en, catKeys.first);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
    padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Strings.t(lang, income ? 'add_income' : 'add_expense'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 28, color: context.textPrimary)),
      const SizedBox(height: 18),
      TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: Strings.t(lang, 'amount'), prefixText: 'Rp ')),
      const SizedBox(height: 12),
      TextField(controller: title, decoration: InputDecoration(labelText: Strings.t(lang, 'transaction_title_field'))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: category, decoration: InputDecoration(labelText: Strings.t(lang, 'category')), items: catKeys.map((k) => DropdownMenuItem(value: Strings.t(AppLang.en, k), child: Text(Strings.t(lang, k)))).toList(), onChanged: (v) => setModalState(() => category = v!)),
      const SizedBox(height: 12),
      TextField(controller: note, decoration: InputDecoration(labelText: Strings.t(lang, 'note_optional'))),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
        final value = double.tryParse(amount.text) ?? 0;
        if (title.text.trim().isEmpty || value <= 0) return;
        ref.read(transactionsProvider.notifier).add(title: title.text.trim(), amount: value, income: income, category: category, note: note.text.trim(), date: DateTime.now());
        Navigator.pop(sheetContext);
      }, child: Text(Strings.t(lang, 'save_transaction')))),
    ]),
  )));
}

String rupiah(double value) => 'Rp ${NumberFormat('#,###', 'id_ID').format(value).replaceAll(',', '.')}';
