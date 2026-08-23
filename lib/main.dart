import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

void main() => runApp(const ProviderScope(child: MyFinanceApp()));

final transactionsProvider = StateNotifierProvider<TransactionController,
    List<FinanceTransaction>>((ref) => TransactionController());

final selectedTabProvider = StateProvider<int>((ref) => 0);

class FinanceTransaction {
  final String title;
  final String category;
  final double amount;
  final bool income;
  final DateTime date;
  const FinanceTransaction({
    required this.title,
    required this.category,
    required this.amount,
    required this.income,
    required this.date,
  });
}

class TransactionController extends StateNotifier<List<FinanceTransaction>> {
  TransactionController()
      : super([
          FinanceTransaction(
            title: 'Gaji Bulanan',
            category: 'Gaji',
            amount: 8500000,
            income: true,
            date: DateTime(2026, 8, 23),
          ),
          FinanceTransaction(
            title: 'Makan siang',
            category: 'Makanan',
            amount: 45000,
            income: false,
            date: DateTime(2026, 8, 23),
          ),
          FinanceTransaction(
            title: 'Transportasi',
            category: 'Transportasi',
            amount: 120000,
            income: false,
            date: DateTime(2026, 8, 22),
          ),
          FinanceTransaction(
            title: 'Belanja bulanan',
            category: 'Belanja',
            amount: 680000,
            income: false,
            date: DateTime(2026, 8, 20),
          ),
        ]);

  void add(String title, double amount, bool income) {
    state = [
      FinanceTransaction(
        title: title,
        category: income ? 'Lainnya' : 'Lainnya',
        amount: amount,
        income: income,
        date: DateTime.now(),
      ),
      ...state,
    ];
  }
}

class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF11151B);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9F43),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A2029),
        ),
        fontFamily: 'sans',
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const pages = <Widget>[
    DashboardPage(),
    TransactionsPage(),
    ReportsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedTabProvider);
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) =>
            ref.read(selectedTabProvider.notifier).state = index,
        backgroundColor: const Color(0xFF151A21),
        indicatorColor: const Color(0xFF3A2D23),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transaksi'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Laporan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    final income = items.where((e) => e.income).fold<double>(0, (s, e) => s + e.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (s, e) => s + e.amount);
    final balance = 2500000 + income - expense;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MINGGU, 23 AGUSTUS', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 6),
              const Text('Selamat pagi, Raka', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            ])),
            IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          ]),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFFFF9F43), borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('SALDO TERKINI', style: TextStyle(color: Color(0xFF3B2717), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1)),
                Icon(Icons.visibility_outlined, color: Colors.brown.shade800, size: 19),
              ]),
              const SizedBox(height: 12),
              Text(rupiah(balance), style: const TextStyle(color: Color(0xFF24170E), fontSize: 31, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(9)), child: const Row(children: [Icon(Icons.trending_up, size: 15, color: Color(0xFF3B2717)), SizedBox(width: 4), Text('8,4% bulan ini', style: TextStyle(color: Color(0xFF3B2717), fontSize: 11, fontWeight: FontWeight.w700))])),
                Text('Saldo awal ${rupiah(2500000)}', style: const TextStyle(color: Color(0xFF70451F), fontSize: 11)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ActionTile(label: 'Pemasukan', icon: Icons.arrow_downward, color: const Color(0xFF214B42), onTap: () => showTransactionDialog(context, ref, true))),
            const SizedBox(width: 12),
            Expanded(child: ActionTile(label: 'Pengeluaran', icon: Icons.arrow_upward, color: const Color(0xFF392C35), onTap: () => showTransactionDialog(context, ref, false))),
          ]),
          const SizedBox(height: 28),
          const SectionHeader(title: 'Ringkasan bulan ini', action: 'Detail'),
          SurfaceCard(child: Row(children: [
            Expanded(child: SummaryValue(label: 'Pemasukan', value: rupiah(income), color: const Color(0xFF65D7A9))),
            const SizedBox(width: 18), Container(width: 1, height: 53, color: const Color(0xFF2B3542)), const SizedBox(width: 18),
            Expanded(child: SummaryValue(label: 'Pengeluaran', value: rupiah(expense), color: Colors.white)),
          ])),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Perkembangan saldo', action: '30 hari'),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rupiah(balance), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(height: 62, child: CustomPaint(painter: SparklinePainter())),
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('01 Agu', style: mutedSmall), Text('10 Agu', style: mutedSmall), Text('20 Agu', style: mutedSmall), Text('Hari ini', style: mutedSmall)]),
          ])),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Transaksi terbaru', action: 'Lihat semua'),
          SurfaceCard(child: Column(children: items.take(4).map((e) => TransactionRow(item: e)).toList())),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Target tabungan', action: 'Kelola'),
          SurfaceCard(color: const Color(0xFF202D2A), child: Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFF294A42), child: Icon(Icons.wb_sunny_outlined, color: Color(0xFF65D7A9))),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Dana liburan', style: TextStyle(fontWeight: FontWeight.w700)), Text('35%', style: TextStyle(color: Color(0xFF65D7A9), fontWeight: FontWeight.w800))]),
              SizedBox(height: 5), Text('Rp 4.200.000 dari Rp 12.000.000', style: TextStyle(color: Color(0xFF94A0B2), fontSize: 11)),
              SizedBox(height: 10), LinearProgressIndicator(value: .35, minHeight: 6, backgroundColor: Color(0xFF35534B), color: Color(0xFF65D7A9), borderRadius: BorderRadius.all(Radius.circular(6))),
            ])),
          ])),
        ],
      ),
    );
  }
}

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    return SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Transaksi', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), const Text('Semua aktivitas keuanganmu', style: TextStyle(color: Color(0xFF94A0B2))),
      const SizedBox(height: 20), TextField(decoration: InputDecoration(hintText: 'Cari transaksi', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Color(0xFF1A2029), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15)), borderSide: BorderSide.none))),
      const SizedBox(height: 16), Wrap(spacing: 8, children: ['Semua', 'Pemasukan', 'Pengeluaran'].map((e) => Chip(label: Text(e), backgroundColor: e == 'Semua' ? const Color(0xFFFF9F43) : const Color(0xFF252D38))).toList()),
      const SizedBox(height: 18), SurfaceCard(child: Column(children: items.map((e) => TransactionRow(item: e)).toList())),
    ]));
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    final expense = items.where((e) => !e.income).fold<double>(0, (s, e) => s + e.amount);
    return SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Laporan', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), const Text('Lihat pola keuanganmu', style: TextStyle(color: Color(0xFF94A0B2))),
      const SizedBox(height: 22), SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Pengeluaran bulan ini', style: TextStyle(color: Color(0xFF94A0B2))), const SizedBox(height: 7), Text(rupiah(expense), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(height: 20), SizedBox(height: 145, child: CustomPaint(painter: BarChartPainter()))])),
      const SizedBox(height: 20), const SectionHeader(title: 'Kategori terbesar', action: 'Bulan ini'),
      SurfaceCard(child: Column(children: const [
        ReportLine(label: 'Belanja', amount: 'Rp 680.000', percent: '57%', color: Color(0xFFFF9F43)),
        ReportLine(label: 'Transportasi', amount: 'Rp 120.000', percent: '10%', color: Color(0xFF65D7A9)),
        ReportLine(label: 'Makanan', amount: 'Rp 45.000', percent: '4%', color: Color(0xFF9B8AFB)),
      ])),
    ]));
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Profil', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)), const SizedBox(height: 22),
    SurfaceCard(child: Row(children: const [CircleAvatar(radius: 28, backgroundColor: Color(0xFFFF9F43), child: Text('R', style: TextStyle(color: Color(0xFF24170E), fontSize: 24, fontWeight: FontWeight.w900))), SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Raka', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Kelola profil dan preferensi', style: TextStyle(color: Color(0xFF94A0B2), fontSize: 12))])])),
    const SizedBox(height: 20), SurfaceCard(child: Column(children: const [SettingRow(icon: Icons.account_balance_wallet_outlined, title: 'Saldo awal', value: 'Rp 2.500.000'), SettingRow(icon: Icons.category_outlined, title: 'Kelola kategori'), SettingRow(icon: Icons.currency_exchange, title: 'Mata uang', value: 'Rupiah (IDR)'), SettingRow(icon: Icons.dark_mode_outlined, title: 'Tema', value: 'Gelap')])),
  ]));
}

class ActionTile extends StatelessWidget { final String label; final IconData icon; final Color color; final VoidCallback onTap; const ActionTile({super.key, required this.label, required this.icon, required this.color, required this.onTap}); @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(height: 70, padding: const EdgeInsets.symmetric(horizontal: 13), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)), child: Row(children: [CircleAvatar(radius: 17, backgroundColor: Colors.black26, child: Icon(icon, size: 19, color: const Color(0xFF65D7A9))), const SizedBox(width: 9), Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)))]))); }
class SectionHeader extends StatelessWidget { final String title; final String action; const SectionHeader({super.key, required this.title, required this.action}); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), Text(action, style: const TextStyle(color: Color(0xFFFF9F43), fontSize: 12, fontWeight: FontWeight.w700))])); }
class SurfaceCard extends StatelessWidget { final Widget child; final Color color; const SurfaceCard({super.key, required this.child, this.color = const Color(0xFF1A2029)}); @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF2B3542))), child: child); }
class SummaryValue extends StatelessWidget { final String label, value; final Color color; const SummaryValue({super.key, required this.label, required this.value, required this.color}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF94A0B2), fontSize: 12)), const SizedBox(height: 7), Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800))]); }
class TransactionRow extends StatelessWidget { final FinanceTransaction item; const TransactionRow({super.key, required this.item}); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [CircleAvatar(radius: 21, backgroundColor: item.income ? const Color(0xFF214B42) : const Color(0xFF392C35), child: Icon(item.income ? Icons.arrow_downward : Icons.shopping_bag_outlined, size: 18, color: item.income ? const Color(0xFF65D7A9) : const Color(0xFFFF9F43))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 4), Text('${item.category} · ${DateFormat('dd MMM yyyy').format(item.date)}', style: const TextStyle(color: Color(0xFF94A0B2), fontSize: 11))])), Text('${item.income ? '+' : '-'}${rupiah(item.amount)}', style: TextStyle(color: item.income ? const Color(0xFF65D7A9) : Colors.white, fontSize: 12, fontWeight: FontWeight.w700))])); }
class ReportLine extends StatelessWidget { final String label, amount, percent; final Color color; const ReportLine({super.key, required this.label, required this.amount, required this.percent, required this.color}); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 10), Expanded(child: Text(label)), Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(width: 12), Text(percent, style: const TextStyle(color: Color(0xFF94A0B2), fontSize: 12))])); }
class SettingRow extends StatelessWidget { final IconData icon; final String title; final String? value; const SettingRow({super.key, required this.icon, required this.title, this.value}); @override Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: const Color(0xFFFF9F43)), title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), trailing: value != null ? Text(value!, style: const TextStyle(color: Color(0xFF94A0B2), fontSize: 12)) : const Icon(Icons.chevron_right, color: Color(0xFF94A0B2))); }
class SparklinePainter extends CustomPainter { @override void paint(Canvas c, Size s) { final p = Paint()..color = const Color(0xFFFF9F43)..strokeWidth = 3..style = PaintingStyle.stroke; final path = Path()..moveTo(0, s.height * .78)..lineTo(s.width * .58, s.height * .46)..lineTo(s.width * .72, s.height * .53)..lineTo(s.width, s.height * .18); c.drawPath(path, p); } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false; }
class BarChartPainter extends CustomPainter { @override void paint(Canvas c, Size s) { final p = Paint()..strokeWidth = 18..strokeCap = StrokeCap.round; final values = [0.46, 0.74, 0.34, 0.9, 0.58, 0.7, 0.43]; for (var i = 0; i < values.length; i++) { p.color = i.isEven ? const Color(0xFFFF9F43) : const Color(0xFF65D7A9); final x = 18.0 + i * (s.width - 36) / 6; c.drawLine(Offset(x, s.height), Offset(x, s.height * (1 - values[i])), p); } } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false; }
const mutedSmall = TextStyle(color: Color(0xFF94A0B2), fontSize: 10);
String rupiah(double value) => 'Rp ${NumberFormat('#,###', 'id_ID').format(value).replaceAll(',', '.')}';

Future<void> showTransactionDialog(BuildContext context, WidgetRef ref, bool income) async {
  final title = TextEditingController(); final amount = TextEditingController();
  await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1A2029), builder: (context) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Tambah ${income ? 'pemasukan' : 'pengeluaran'}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), const SizedBox(height: 20),
    TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ')), const SizedBox(height: 12),
    TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')), const SizedBox(height: 20),
    SizedBox(width: double.infinity, child: FilledButton(onPressed: () { final value = double.tryParse(amount.text.replaceAll('.', '')) ?? 0; if (title.text.isNotEmpty && value > 0) { ref.read(transactionsProvider.notifier).add(title.text, value, income); Navigator.pop(context); } }, child: const Text('Simpan transaksi'))),
  ])));
}