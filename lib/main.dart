import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
final tabProvider = StateProvider<int>((ref) => 0);
final onboardingProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('onboarding_done') ?? false);

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
          FinanceTransaction(title: 'Gaji Bulanan', category: 'Pemasukan', note: 'Gaji bulan Agustus', amount: 8500000, income: true, date: DateTime(2026, 8, 24, 8, 30)),
          FinanceTransaction(title: 'Belanja kebutuhan', category: 'Belanja', note: 'Kebutuhan rumah', amount: 250000, income: false, date: DateTime(2026, 8, 24, 12, 30)),
          FinanceTransaction(title: 'Kopi sore', category: 'Makanan', note: '', amount: 25000, income: false, date: DateTime(2026, 8, 24, 15, 20)),
          FinanceTransaction(title: 'Freelance design', category: 'Pemasukan', note: '', amount: 500000, income: true, date: DateTime(2026, 8, 23, 10, 0)),
          FinanceTransaction(title: 'Transportasi', category: 'Transport', note: '', amount: 120000, income: false, date: DateTime(2026, 8, 23, 8, 15)),
          FinanceTransaction(title: 'Tagihan internet', category: 'Tagihan', note: '', amount: 350000, income: false, date: DateTime(2026, 8, 20)),
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F7FB),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7655D8), brightness: Brightness.light),
        fontFamily: 'Satoshi',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white,
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
  final slides = const [
    ('Kelola keuanganmu\nlebih mudah', 'Catat pemasukan, pengeluaran, dan pantau perkembangan saldo.'),
    ('Semua transaksi\ndalam satu tempat', 'Pantau aktivitas keuangan dengan cara yang lebih rapi dan sederhana.'),
    ('Pahami keuanganmu', 'Lihat laporan untuk mengambil keputusan finansial yang lebih baik.'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = page == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('MY FINANCE', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w900, letterSpacing: 2)),
              TextButton(onPressed: () => _finish(), child: const Text('Lewati')),
            ]),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 330, width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E1FF), borderRadius: BorderRadius.circular(40),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF1EDFF), Color(0xFFD4C7FF)]),
                  ),
                  child: Stack(children: [
                    Positioned(top: 42, left: 28, child: _orb(const Color(0xFFB9A7FF), 54)),
                    Positioned(top: 88, right: 40, child: _orb(const Color(0xFF8D75E9), 90)),
                    Positioned(bottom: 44, left: 80, child: _orb(colors.primary, 120)),
                    Center(child: Icon(last ? Icons.insights_rounded : page == 1 ? Icons.receipt_long_rounded : Icons.account_balance_wallet_rounded, size: 94, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 40),
                Text(slides[page].$1, style: const TextStyle(fontFamily: 'DM Serif Display', fontSize: 36, height: 1.08, color: Color(0xFF25212E))),
                const SizedBox(height: 16),
                Text(slides[page].$2, style: TextStyle(fontSize: 16, height: 1.5, color: Colors.grey.shade600)),
              ]),
            ),
            Row(children: [
              ...List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 220), margin: const EdgeInsets.only(right: 6), width: i == page ? 28 : 7, height: 7, decoration: BoxDecoration(color: i == page ? colors.primary : const Color(0xFFD8D2E5), borderRadius: BorderRadius.circular(20)))),
              const Spacer(),
              FilledButton.icon(onPressed: () => last ? _finish() : setState(() => page++), icon: Icon(last ? Icons.check : Icons.arrow_forward), label: Text(last ? 'Mulai sekarang' : 'Lanjutkan')),
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
  static const pages = [HomePage(), TransactionsPage(), ReportsPage(), ProfilePage()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8E0FF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transaksi'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Laporan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
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
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final balance = 50000000 + income - expense;
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE, d MMMM', 'id_ID').format(DateTime.now()), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 5),
          const Text('Selamat pagi, Raka', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 27, color: Color(0xFF25212E))),
        ])),
        CircleAvatar(radius: 24, backgroundColor: primary, child: const Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
      ]),
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: primary.withOpacity(.25), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('TOTAL SALDO', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.bold)),
            Icon(Icons.more_horiz, color: Colors.white.withOpacity(.8)),
          ]),
          const SizedBox(height: 16),
          Text(rupiah(balance), style: const TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.trending_up, color: Color(0xFFB9F4C2), size: 18), const SizedBox(width: 5), const Text('+12.4%', style: TextStyle(color: Color(0xFFB9F4C2), fontWeight: FontWeight.bold)), const SizedBox(width: 6), Text('dibanding bulan lalu', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12))]),
        ]),
      ),
      const SizedBox(height: 26),
      const SectionTitle('Aksi cepat'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: QuickAction(icon: Icons.arrow_downward, label: 'Pemasukan', color: const Color(0xFFE7F7EA), iconColor: const Color(0xFF24A148), onTap: () => showTransactionForm(context, ref, true))),
        const SizedBox(width: 12),
        Expanded(child: QuickAction(icon: Icons.arrow_upward, label: 'Pengeluaran', color: const Color(0xFFFBE8ED), iconColor: const Color(0xFFE05270), onTap: () => showTransactionForm(context, ref, false))),
        const SizedBox(width: 12),
        Expanded(child: QuickAction(icon: Icons.more_horiz, label: 'Lainnya', color: const Color(0xFFEDE9FF), iconColor: primary, onTap: () => ref.read(tabProvider.notifier).state = 3)),
      ]),
      const SizedBox(height: 28),
      Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: const Color(0xFFF0ECFF), borderRadius: BorderRadius.circular(20)), child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primary.withOpacity(.12), shape: BoxShape.circle), child: Icon(Icons.auto_awesome, color: primary)),
        const SizedBox(width: 13),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Financial insight', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Pengeluaranmu turun 8% dibanding bulan lalu.', style: TextStyle(fontSize: 13, height: 1.35))])),
      ])),
      const SizedBox(height: 28),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const SectionTitle('Transaksi terbaru'), TextButton(onPressed: () => ref.read(tabProvider.notifier).state = 1, child: const Text('Lihat semua'))]),
      const SizedBox(height: 4),
      ...items.take(4).map((item) => TransactionTile(item: item)),
      const SizedBox(height: 18),
      const SectionTitle('Ringkasan bulan ini'),
      const SizedBox(height: 12),
      SummaryCard(income: income, expense: expense),
    ]));
  }
}

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});
  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}
class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  String query = '';
  String filter = 'Semua';
  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider);
    final items = all.where((e) => (filter == 'Semua' || (filter == 'Pemasukan' ? e.income : !e.income)) && e.title.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      const Text('Transaksi', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32)),
      Text('Semua aktivitas keuanganmu', style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 22),
      TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(hintText: 'Cari transaksi', prefixIcon: Icon(Icons.search))),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['Semua', 'Pemasukan', 'Pengeluaran']
              .map<Widget>(
                (v) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(v),
                    selected: filter == v,
                    onSelected: (_) => setState(() => filter = v),
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
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final groups = <String, double>{};
    for (final item in items.where((e) => !e.income)) groups[item.category] = (groups[item.category] ?? 0) + item.amount;
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
      const Text('Laporan', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32)),
      Text('Agustus 2026', style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 22),
      SummaryCard(income: income, expense: expense),
      const SizedBox(height: 24),
      const SectionTitle('Arus kas bulan ini'),
      const SizedBox(height: 12),
      Container(height: 190, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: CustomPaint(painter: SimpleChartPainter(primary: Theme.of(context).colorScheme.primary))),
      const SizedBox(height: 24),
      const SectionTitle('Pengeluaran berdasarkan kategori'),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(children: groups.entries.map((e) => ReportRow(label: e.key, amount: e.value, total: expense)).toList())),
    ]));
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
    const Text('Profil', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32)),
    const SizedBox(height: 22),
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: const Row(children: [CircleAvatar(radius: 31, backgroundColor: Color(0xFF7655D8), child: Text('R', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold))), SizedBox(width: 15), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Raka', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Kelola akun keuanganmu')])])),
    const SizedBox(height: 26),
    const SectionTitle('Keuangan'),
    const SizedBox(height: 10),
    SettingList(items: const [['Target tabungan', Icons.savings_outlined], ['Kategori', Icons.category_outlined], ['Akun / Dompet', Icons.account_balance_wallet_outlined], ['Piutang', Icons.people_outline]]),
    const SizedBox(height: 24),
    const SectionTitle('Aplikasi'),
    const SizedBox(height: 10),
    SettingList(items: const [['Tampilan', Icons.palette_outlined], ['Notifikasi', Icons.notifications_none], ['Backup data', Icons.cloud_upload_outlined]]),
  ]);
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF25212E)));
}

class QuickAction extends StatelessWidget {
  final IconData icon; final String label; final Color color, iconColor; final VoidCallback onTap;
  const QuickAction({super.key, required this.icon, required this.label, required this.color, required this.iconColor, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(19), child: Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(19)), child: Column(children: [Icon(icon, color: iconColor), const SizedBox(height: 7), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))])));
}

class TransactionTile extends StatelessWidget {
  final FinanceTransaction item;
  const TransactionTile({super.key, required this.item});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(color: item.income ? const Color(0xFFE7F7EA) : const Color(0xFFF1EDFF), borderRadius: BorderRadius.circular(15)), child: Icon(item.income ? Icons.arrow_downward : Icons.shopping_bag_outlined, color: item.income ? const Color(0xFF24A148) : Theme.of(context).colorScheme.primary, size: 20)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text('${item.category} · ${DateFormat('dd MMM, HH:mm', 'id_ID').format(item.date)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))])),
    Text('${item.income ? '+' : '-'}${rupiah(item.amount)}', style: TextStyle(fontWeight: FontWeight.bold, color: item.income ? const Color(0xFF24A148) : const Color(0xFF25212E))),
  ]));
}

class SummaryCard extends StatelessWidget {
  final double income, expense;
  const SummaryCard({super.key, required this.income, required this.expense});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: Row(children: [
    Expanded(child: _summary('Pemasukan', rupiah(income), const Color(0xFF24A148))),
    Container(width: 1, height: 44, color: Colors.grey.shade200),
    Expanded(child: _summary('Pengeluaran', rupiah(expense), const Color(0xFFE05270))),
    Container(width: 1, height: 44, color: Colors.grey.shade200),
    Expanded(child: _summary('Tabungan', '${((income - expense) / (income == 0 ? 1 : income) * 100).round()}%', Theme.of(context).colorScheme.primary)),
  ]));
  Widget _summary(String title, String value, Color color) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)), const SizedBox(height: 7), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))]));
}

class ReportRow extends StatelessWidget {
  final String label; final double amount, total;
  const ReportRow({super.key, required this.label, required this.amount, required this.total});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), Text('${rupiah(amount)} · ${(amount / total * 100).round()}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))]), const SizedBox(height: 8), LinearProgressIndicator(value: amount / total, minHeight: 7, borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.primary.withOpacity(.75), backgroundColor: const Color(0xFFF0ECF7))]));
}

class SettingList extends StatelessWidget {
  final List<List<Object>> items;
  const SettingList({super.key, required this.items});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      children: items
          .map<Widget>(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item[1] as IconData,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(item[0] as String),
              trailing: const Icon(Icons.chevron_right, size: 20),
            ),
          )
          .toList(),
    ),
  );
}

class SimpleChartPainter extends CustomPainter {
  final Color primary;
  SimpleChartPainter({required this.primary});
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFEDEAF2)..strokeWidth = 1;
    for (var i = 1; i < 5; i++) canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5), grid);
    final line = Paint()..color = primary..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height * .72)..cubicTo(size.width * .16, size.height * .50, size.width * .2, size.height * .62, size.width * .35, size.height * .48)..cubicTo(size.width * .5, size.height * .32, size.width * .62, size.height * .6, size.width * .76, size.height * .28)..cubicTo(size.width * .84, size.height * .18, size.width * .92, size.height * .35, size.width, size.height * .15);
    canvas.drawPath(path, line);
  }
  @override
  bool shouldRepaint(covariant SimpleChartPainter oldDelegate) => oldDelegate.primary != primary;
}

Future<void> showTransactionForm(BuildContext context, WidgetRef ref, bool income) async {
  final amount = TextEditingController(), title = TextEditingController(), note = TextEditingController();
  String category = income ? 'Pemasukan' : 'Makanan';
  await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFFF8F7FB), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
    padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tambah ${income ? 'pemasukan' : 'pengeluaran'}', style: const TextStyle(fontFamily: 'DM Serif Display', fontSize: 28)),
      const SizedBox(height: 18),
      TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ')),
      const SizedBox(height: 12),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Judul transaksi')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Kategori'), items: (income ? ['Pemasukan', 'Freelance', 'Bonus'] : ['Makanan', 'Belanja', 'Transport', 'Tagihan', 'Lainnya']).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setModalState(() => category = v!)),
      const SizedBox(height: 12),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
        final value = double.tryParse(amount.text) ?? 0;
        if (title.text.trim().isEmpty || value <= 0) return;
        ref.read(transactionsProvider.notifier).add(title: title.text.trim(), amount: value, income: income, category: category, note: note.text.trim(), date: DateTime.now());
        Navigator.pop(sheetContext);
      }, child: const Text('Simpan transaksi'))),
    ]),
  )));
}

String rupiah(double value) => 'Rp ${NumberFormat('#,###', 'id_ID').format(value).replaceAll(',', '.')}';