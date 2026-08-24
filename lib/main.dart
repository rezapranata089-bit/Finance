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
  static const pages = [HomePage(), ReportsPage(), TransactionsPage(), ProfilePage()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(0, Icons.home_filled, 'Home', tab, ref),
            _navItem(1, Icons.bar_chart, 'Statistic', tab, ref),
            GestureDetector(
              onTap: () {},
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6F6A6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.black),
              ),
            ),
            _navItem(2, Icons.credit_card, 'Card', tab, ref),
            _navItem(3, Icons.person_outline, 'Profile', tab, ref),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, int currentTab, WidgetRef ref) {
    final isSelected = currentTab == index;
    return GestureDetector(
      onTap: () => ref.read(tabProvider.notifier).state = index,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSelected ? Colors.black : Colors.grey, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: isSelected ? Colors.black : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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
    
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200)),
                child: const Icon(Icons.menu, size: 20),
              ),
              const Text('My Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200)),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 20),
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFD6F6A6), shape: BoxShape.circle),
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
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20, height: 14,
                    decoration: BoxDecoration(color: const Color(0xFFD6F6A6), borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 8),
                  const Text('**** 3425', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Center(child: Text('Your Balance', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500))),
          const SizedBox(height: 8),
          Center(child: Text(rupiah(balance), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1))),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: primary),
                  const SizedBox(width: 6),
                  Text('You saved Rp 290.000 in last Month >', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _actionBtn(context, Icons.arrow_outward, 'Send', const Color(0xFFD6F6A6), Colors.black, () => showTransactionForm(context, ref, false)),
              _actionBtn(context, Icons.south_west, 'Request', Colors.white, Colors.black, () => showTransactionForm(context, ref, true)),
              _actionBtn(context, Icons.swap_horiz, 'Exchange', Colors.white, Colors.black, () => ref.read(tabProvider.notifier).state = 2),
              _actionBtn(context, Icons.more_horiz, 'More', Colors.white, Colors.black, () => ref.read(tabProvider.notifier).state = 3),
            ],
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Top Merchants', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text('View all >', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Discount Up To 80%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Festive Season Gift', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFF4EDFF), shape: BoxShape.circle),
                  child: Icon(Icons.shopping_bag_rounded, color: primary, size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Transaction History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text('View all >', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('TODAY', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...items.take(4).map((item) => TransactionTile(item: item)),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, Color bgColor, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 68,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: bgColor == Colors.white ? Border.all(color: Colors.grey.shade200) : null,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
  ]));
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF25212E)));
}

// Removed QuickAction as it is no longer used

class TransactionTile extends StatelessWidget {
  final FinanceTransaction item;
  const TransactionTile({super.key, required this.item});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: const BoxDecoration(color: Color(0xFF1B1B1B), shape: BoxShape.circle),
          child: Center(
            child: Text(
              item.title.substring(0, 1).toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black)),
              const SizedBox(height: 4),
              Text(DateFormat('hh:mm a').format(item.date), style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${item.income ? '+' : '-'}${rupiah(item.amount)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black),
            ),
            const SizedBox(height: 4),
            Text(item.income ? 'Receive' : 'Transfer', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    ),
  );
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