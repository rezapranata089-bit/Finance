import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
final selectedCardProvider = StateProvider<int>((ref) => 0);
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

class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? tint;
  final double blur;
  final double intensity;
  final bool useBlur;
  final Color? borderColor;
  const LiquidGlass({super.key, required this.child, this.borderRadius = 20, this.tint, this.blur = 6, this.intensity = 1.0, this.useBlur = false, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final base = tint ?? Colors.white;
    final topOpacity = ((isDark ? 0.34 : 0.44) * intensity).clamp(0.0, 1.0);
    final bottomOpacity = ((isDark ? 0.16 : 0.20) * intensity).clamp(0.0, 1.0);
    final glassBody = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withOpacity(topOpacity),
            base.withOpacity(bottomOpacity),
          ],
        ),
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(isDark ? 0.16 : 0.55),
          width: 1,
        ),
      ),
      child: child,
    );
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(isDark ? 0.05 : 0.55),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: useBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: glassBody,
                )
              : glassBody,
        ),
      ),
    );
  }
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
    'cashback_title': {AppLang.en: 'Cashback 15%', AppLang.id: 'Cashback 15%'},
    'cashback_subtitle': {AppLang.en: 'Grocery partners', AppLang.id: 'Merchant belanja'},
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
          filled: true, fillColor: const Color(0xFFF1EEF7),
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: theme.primary, width: 1.4)),
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
        textTheme: Typography.material2021(platform: TargetPlatform.android)
            .white
            .apply(fontFamily: 'Satoshi', bodyColor: Colors.white, displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF1E1B27),
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark ? const Color(0xFF1E1B27) : Colors.white,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(0.9).clamp(0.85, 1.0),
              ),
            ),
            child: child!,
          ),
        );
      },
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(key: ValueKey<int>(tab), child: pages[tab]),
      ),
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
            _navItem(context, 2, SolarIconsOutline.billList, SolarIconsBold.billList, Strings.t(lang, 'nav_card'), tab, ref),
            _navItem(context, 3, SolarIconsOutline.user, SolarIconsBold.user, Strings.t(lang, 'nav_profile'), tab, ref),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int index, IconData iconOutline, IconData iconBold, String label, int currentTab, WidgetRef ref) {
    final isSelected = currentTab == index;
    final color = isSelected ? context.textPrimary : context.iconMuted;
    return GestureDetector(
      onTap: () => ref.read(tabProvider.notifier).state = index,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  isSelected ? iconBold : iconOutline,
                  key: ValueKey<bool>(isSelected),
                  color: color,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(fontSize: 10, color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ],
        ),
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

    final topInset = MediaQuery.paddingOf(context).top;
    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.26) : Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(children: [
              Container(
                  padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 32),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(primary.withOpacity(isDark ? 0.22 : 0.14), context.cardColor).withOpacity(isDark ? 0.86 : 0.82),
                        Color.alphaBlend(primary.withOpacity(isDark ? 0.16 : 0.08), context.cardColor).withOpacity(isDark ? 0.68 : 0.58),
                      ],
                    ),
                  ),
                  child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const HamburgerMorphMenu(),
                    Text(Strings.t(lang, 'my_account'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.22 : 0.07),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: LiquidGlass(
                              borderRadius: 999,
                              tint: isDark ? Colors.black : null,
                              intensity: isDark ? 1.6 : 1.0,
                              borderColor: isDark ? context.borderColor : null,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(SolarIconsOutline.bell, size: 20, color: context.textPrimary),
                              ),
                            ),
                          ),
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
                const Center(child: CardSelectorButton()),
                const SizedBox(height: 24),
                Center(child: Text(Strings.t(lang, 'your_balance'), style: TextStyle(color: context.textMuted, fontSize: 13, fontWeight: FontWeight.w500))),
                const SizedBox(height: 8),
                Center(child: Text(rupiah(balance), style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1, color: context.textPrimary))),
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
                    _actionBtn(context, SolarIconsOutline.arrowLeftDown, Strings.t(lang, 'request'), primaryStyle: false, blackGlassInDark: true, onTap: () => showTransactionForm(context, ref, true)),
                    _actionBtn(context, SolarIconsOutline.transferHorizontal, Strings.t(lang, 'exchange'), primaryStyle: false, blackGlassInDark: true, onTap: () => ref.read(tabProvider.notifier).state = 2),
                    _actionBtn(context, SolarIconsOutline.menuDots, Strings.t(lang, 'more'), primaryStyle: false, blackGlassInDark: true, onTap: () => ref.read(tabProvider.notifier).state = 3),
                  ],
                ),
              ],
            ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: BottomRoundedBorderPainter(
                      color: isDark ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.6),
                      radius: 32,
                    ),
                  ),
                ),
              ),
            ]),
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
                Builder(builder: (context) {
                  final promos = [
                    (Strings.t(lang, 'discount_title'), Strings.t(lang, 'discount_subtitle'), SolarIconsBold.bag2),
                    (Strings.t(lang, 'cashback_title'), Strings.t(lang, 'cashback_subtitle'), SolarIconsBold.wallet),
                  ];
                  final cardWidth = MediaQuery.sizeOf(context).width * 0.78;
                  return SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: promos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final promo = promos[i];
                        return Container(
                          width: cardWidth,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color.alphaBlend(primary.withOpacity(isDark ? 0.38 : 0.22), context.cardColor),
                                context.cardColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(promo.$1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text(promo.$2, style: TextStyle(color: context.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                                child: Icon(promo.$3, color: primary, size: 24),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
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

  Widget _actionBtn(BuildContext context, IconData icon, String label, {required bool primaryStyle, required VoidCallback onTap, bool blackGlassInDark = false}) {
    final accent = Theme.of(context).colorScheme.secondary;
    final isDark = context.isDark;
    final useBlackGlass = blackGlassInDark && isDark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            width: 68,
            height: 42,
            child: LiquidGlass(
              borderRadius: 16,
              tint: useBlackGlass ? Colors.black : (primaryStyle ? accent : null),
              intensity: useBlackGlass ? 1.6 : (primaryStyle ? (isDark ? 2.3 : 1.8) : 1.0),
              borderColor: useBlackGlass ? context.borderColor : null,
              child: Center(
                child: Icon(icon, color: useBlackGlass ? Colors.white : (primaryStyle ? Colors.black : context.textPrimary), size: 22),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
        ],
      ),
    );
  }
}

class HamburgerMorphMenu extends ConsumerStatefulWidget {
  const HamburgerMorphMenu({super.key});
  @override
  ConsumerState<HamburgerMorphMenu> createState() => _HamburgerMorphMenuState();
}

class _HamburgerMorphMenuState extends ConsumerState<HamburgerMorphMenu> with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  late final AnimationController _controller = AnimationController(vsync: this, value: 0);
  bool _open = false;
  bool _pressed = false;

  static const _closedSize = Size(40, 40);
  static const _openSize = Size(183, 208);
  static const _openCurve = Cubic(0.34, 1.25, 0.64, 1.0);
  static const _closeCurve = Cubic(0.22, 1.0, 0.36, 1.0);

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _toggle() async {
    if (_open) {
      await _controller.animateTo(0, duration: const Duration(milliseconds: 250), curve: _closeCurve);
      _removeOverlay();
      setState(() => _open = false);
      return;
    }
    setState(() => _open = true);
    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggle)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.topLeft,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                child: _MorphMenuContent(onSelect: _select),
                builder: (context, menuChild) {
                  final t = _controller.value.clamp(0.0, 1.0);
                  final size = Size.lerp(_closedSize, _openSize, t)!;
                  const radius = 20.0;
                  final iconOpacity = (1 - t / 0.45).clamp(0.0, 1.0);
                  final menuOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
                  final menuOffset = (1 - menuOpacity) * 14;
                  final glassT = Curves.easeOut.transform(t);
                  final showBlur = glassT > 0.85;
                  return Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: LiquidGlass(
                        borderRadius: radius,
                        tint: context.cardColor,
                        intensity: glassT > 0.85 ? 1.6 : 1.0,
                        blur: 6,
                        useBlur: showBlur,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: Stack(
                            children: [
                              if (iconOpacity > 0)
                                Positioned(
                                  top: 0, left: 0, width: 40, height: 40,
                                  child: Opacity(
                                    opacity: iconOpacity,
                                    child: const Center(child: Icon(SolarIconsOutline.hamburgerMenu, size: 20)),
                                  ),
                                ),
                              if (menuOpacity > 0)
                                Opacity(
                                  opacity: menuOpacity,
                                  child: Transform.translate(
                                    offset: Offset(menuOffset, menuOffset * -0.3),
                                    child: menuChild,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    await _controller.animateTo(1, duration: const Duration(milliseconds: 350), curve: _openCurve);
  }

  void _select(VoidCallback action) {
    _toggle();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _toggle,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Opacity(
          opacity: _open ? 0 : 1,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.22 : 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LiquidGlass(
              borderRadius: 999,
              tint: isDark ? Colors.black : null,
              intensity: isDark ? 1.6 : 1.0,
              borderColor: isDark ? context.borderColor : null,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(SolarIconsOutline.hamburgerMenu, size: 20, color: context.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphMenuContent extends ConsumerWidget {
  final void Function(VoidCallback action) onSelect;
  const _MorphMenuContent({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      (SolarIconsOutline.user, Strings.t(lang, 'nav_profile'), () => ref.read(tabProvider.notifier).state = 3),
      (
        isDark ? SolarIconsOutline.sun : SolarIconsOutline.moon,
        isDark ? Strings.t(lang, 'light') : Strings.t(lang, 'dark'),
        () => ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark,
      ),
      (SolarIconsOutline.palette, Strings.t(lang, 'appearance'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionPage()))),
      (Icons.language, Strings.t(lang, 'language'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionPage()))),
      (SolarIconsOutline.bell, Strings.t(lang, 'notifications'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map<Widget>((item) => ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
                  onTap: () => onSelect(item.$3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  minLeadingWidth: 0,
                  leading: Icon(item.$1, size: 18, color: primary),
                  title: Text(item.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                ))
            .toList(),
      ),
    );
  }
}

class CardSelectorButton extends ConsumerStatefulWidget {
  const CardSelectorButton({super.key});
  @override
  ConsumerState<CardSelectorButton> createState() => _CardSelectorButtonState();
}

class _CardSelectorButtonState extends ConsumerState<CardSelectorButton> with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  late final AnimationController _controller = AnimationController(vsync: this, value: 0);
  bool _open = false;

  static const _cards = [
    ('**** 3425', 'Main Wallet'),
    ('**** 7810', 'Savings'),
    ('**** 2290', 'Business'),
  ];

  static const _closedSize = Size(130, 30);
  static final _openSize = Size(196, (_cards.length + 1) * 42.0 + 9);
  static const _openCurve = Cubic(0.34, 1.25, 0.64, 1.0);
  static const _closeCurve = Cubic(0.22, 1.0, 0.36, 1.0);

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _toggle() async {
    if (_open) {
      await _controller.animateTo(0, duration: const Duration(milliseconds: 250), curve: _closeCurve);
      _removeOverlay();
      setState(() => _open = false);
      return;
    }
    setState(() => _open = true);
    final selected = ref.read(selectedCardProvider);
    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggle)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.topCenter,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                child: _CardMorphContent(
                  cards: _cards,
                  selected: selected,
                  onSelect: _select,
                  onAdd: _toggle,
                ),
                builder: (context, menuChild) {
                  final t = _controller.value.clamp(0.0, 1.0);
                  final size = Size.lerp(_closedSize, _openSize, t)!;
                  const radius = 18.0;
                  final closedOpacity = (1 - t / 0.4).clamp(0.0, 1.0);
                  final openOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
                  final openOffset = (1 - openOpacity) * 12;
                  final glassT = Curves.easeOut.transform(t);
                  final showBlur = glassT > 0.8;
                  return Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: LiquidGlass(
                        borderRadius: radius,
                        tint: context.cardColor,
                        intensity: glassT > 0.8 ? 1.6 : 1.0,
                        blur: 6,
                        useBlur: showBlur,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: Stack(
                            children: [
                              if (closedOpacity > 0)
                                Positioned(
                                  left: (size.width - _closedSize.width) / 2,
                                  top: 0,
                                  width: _closedSize.width,
                                  height: _closedSize.height,
                                  child: Opacity(
                                    opacity: closedOpacity,
                                    child: _ClosedCardChip(cardLabel: _cards[selected].$1),
                                  ),
                                ),
                              if (openOpacity > 0)
                                Opacity(
                                  opacity: openOpacity,
                                  child: Transform.translate(
                                    offset: Offset(0, openOffset),
                                    child: menuChild,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
    await _controller.animateTo(1, duration: const Duration(milliseconds: 340), curve: _openCurve);
  }

  void _select(int index) {
    _toggle();
    ref.read(selectedCardProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedCardProvider);
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _toggle,
        child: Opacity(
          opacity: _open ? 0 : 1,
          child: _ClosedCardChip(cardLabel: _cards[selected].$1, showArrow: true),
        ),
      ),
    );
  }
}

class _ClosedCardChip extends StatelessWidget {
  final String cardLabel;
  final bool showArrow;
  const _ClosedCardChip({required this.cardLabel, this.showArrow = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: showArrow ? context.cardColor : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: showArrow ? Border.all(color: context.borderColor) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22, height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
            child: const Icon(SolarIconsBold.wallet, size: 12, color: Colors.black87),
          ),
          const SizedBox(width: 8),
          Text(cardLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
          if (showArrow) ...[
            const SizedBox(width: 4),
            Icon(SolarIconsOutline.altArrowDown, size: 16, color: context.iconMuted),
          ],
        ],
      ),
    );
  }
}

class _CardMorphContent extends StatelessWidget {
  final List<(String, String)> cards;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  const _CardMorphContent({required this.cards, required this.selected, required this.onSelect, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...cards.asMap().entries.map((e) {
            final isSelected = e.key == selected;
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              onTap: () => onSelect(e.key),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              minLeadingWidth: 0,
              leading: Icon(SolarIconsOutline.card, size: 16, color: isSelected ? primary : context.iconMuted),
              title: Text(e.value.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
              trailing: isSelected ? Icon(SolarIconsBold.checkCircle, size: 16, color: primary) : null,
            );
          }),
          Divider(height: 1, indent: 12, endIndent: 12, color: context.borderColor),
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            onTap: onAdd,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            minLeadingWidth: 0,
            leading: Icon(SolarIconsOutline.addCircle, size: 16, color: primary),
            title: Text('Tambah kartu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
          ),
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
    return SafeArea(top: false, child: ListView(padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24), children: [
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
    return SafeArea(top: false, child: ListView(padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24), children: [
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
    return SafeArea(top: false, child: ListView(padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24), children: [
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
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: isDark ? Colors.white : Colors.black),
                      ),
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
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: context.textPrimary),
                      ),
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

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final bg = isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
    final cardBg = isDark ? const Color(0xFF1E1B27) : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final notifications = [
      (SolarIconsBold.wallet, 'Pemasukan diterima', 'Gaji bulanan sebesar Rp 8.500.000 telah masuk', '08:30'),
      (SolarIconsBold.bag2, 'Diskon spesial', 'Diskon hingga 80% untuk musim perayaan', 'Kemarin'),
      (SolarIconsBold.stars, 'Target tabungan', 'Kamu berhasil menghemat Rp 290.000 bulan lalu', '2 hari lalu'),
    ];

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
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: context.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(Strings.t(lang, 'notifications'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: notifications.isEmpty
                  ? Center(child: Text(Strings.t(lang, 'not_available').replaceAll('{name}', Strings.t(lang, 'notifications')), style: TextStyle(color: context.textMuted)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = notifications[i];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                                child: Icon(item.$1, color: primary, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.$2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text(item.$3, style: TextStyle(color: context.textMuted, fontSize: 12, height: 1.4)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(item.$4, style: TextStyle(color: context.textFaint, fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      },
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

class BottomRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  const BottomRoundedBorderPainter({required this.color, required this.radius, this.strokeWidth = 1.2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height - radius)
      ..arcToPoint(Offset(radius, size.height), radius: Radius.circular(radius), clockwise: false)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(Offset(size.width, size.height - radius), radius: Radius.circular(radius), clockwise: false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BottomRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius || oldDelegate.strokeWidth != strokeWidth;
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
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
    padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
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
