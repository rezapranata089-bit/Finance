import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

void main() => runApp(const ProviderScope(child: MyFinanceApp()));

final transactionsProvider = StateNotifierProvider<TransactionController,
    List<FinanceTransaction>>((ref) => TransactionController());

final selectedTabProvider = StateProvider<int>((ref) => 0);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);
final accentColorProvider = StateProvider<Color>((ref) => accentPresets.first);

const accentPresets = <Color>[
  Color(0xFFFF9F43),
  Color(0xFF5B8DEF),
  Color(0xFF9B8AFB),
  Color(0xFF65D7A9),
  Color(0xFFFF6B81),
  Color(0xFFFFC24B),
  Color(0xFF4FD1E8),
];

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
        category: 'Lainnya',
        amount: amount,
        income: income,
        date: DateTime.now(),
      ),
      ...state,
    ];
  }
}

class AppColors extends ThemeExtension<AppColors> {
  final Color accent;
  final Color onAccent;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color positive;

  const AppColors({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.positive,
  });

  @override
  AppColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? positive,
  }) {
    return AppColors(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      positive: positive ?? this.positive,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

AppColors _palette(Brightness brightness, Color accent) {
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : const Color(0xFF241708);
  if (brightness == Brightness.dark) {
    return AppColors(
      accent: accent,
      onAccent: onAccent,
      background: const Color(0xFF11151B),
      surface: const Color(0xFF1A2029),
      surfaceAlt: const Color(0xFF202D2A),
      border: const Color(0xFF2B3542),
      textPrimary: Colors.white,
      textMuted: const Color(0xFF94A0B2),
      positive: const Color(0xFF65D7A9),
    );
  }
  return AppColors(
    accent: accent,
    onAccent: onAccent,
    background: const Color(0xFFF4F5F8),
    surface: Colors.white,
    surfaceAlt: const Color(0xFFEAF7F1),
    border: const Color(0xFFE3E7EE),
    textPrimary: const Color(0xFF171B22),
    textMuted: const Color(0xFF6C7686),
    positive: const Color(0xFF2E9E75),
  );
}

ThemeData _buildTheme(Brightness brightness, Color accent) {
  final palette = _palette(brightness, accent);
  final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: palette.background,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: brightness),
    extensions: [palette],
  );
}

class MyFinanceApp extends ConsumerWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light, accent),
      darkTheme: _buildTheme(Brightness.dark, accent),
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
    final colors = context.colors;
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) =>
            ref.read(selectedTabProvider.notifier).state = index,
        backgroundColor: colors.surface,
        indicatorColor: colors.accent.withOpacity(0.18),
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
    final colors = context.colors;
    final income = items.where((e) => e.income).fold<double>(0, (s, e) => s + e.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (s, e) => s + e.amount);
    final balance = 2500000 + income - expense;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MINGGU, 23 AGUSTUS', style: TextStyle(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
              const SizedBox(height: 6),
              Text('Selamat pagi, Raka', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colors.textPrimary)),
            ])),
            IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          ]),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.accent, Color.lerp(colors.accent, Colors.black, 0.25)!],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: colors.accent.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 12))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('SALDO TERKINI', style: TextStyle(color: colors.onAccent.withOpacity(0.75), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.1)),
                Icon(Icons.visibility_outlined, color: colors.onAccent.withOpacity(0.8), size: 19),
              ]),
              const SizedBox(height: 12),
              Text(rupiah(balance), style: TextStyle(color: colors.onAccent, fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: colors.onAccent.withOpacity(0.16), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.trending_up, size: 15, color: colors.onAccent),
                    const SizedBox(width: 4),
                    Text('8,4% bulan ini', style: TextStyle(color: colors.onAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
                Text('Saldo awal ${rupiah(2500000)}', style: TextStyle(color: colors.onAccent.withOpacity(0.75), fontSize: 11)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ActionTile(label: 'Pemasukan', icon: Icons.arrow_downward, background: colors.surfaceAlt, iconColor: colors.positive, onTap: () => showTransactionDialog(context, ref, true))),
            const SizedBox(width: 12),
            Expanded(child: ActionTile(label: 'Pengeluaran', icon: Icons.arrow_upward, background: colors.surface, iconColor: colors.accent, onTap: () => showTransactionDialog(context, ref, false))),
          ]),
          const SizedBox(height: 28),
          const SectionHeader(title: 'Ringkasan bulan ini', action: 'Detail'),
          SurfaceCard(child: Row(children: [
            Expanded(child: SummaryValue(label: 'Pemasukan', value: rupiah(income), color: colors.positive)),
            const SizedBox(width: 18), Container(width: 1, height: 53, color: colors.border), const SizedBox(width: 18),
            Expanded(child: SummaryValue(label: 'Pengeluaran', value: rupiah(expense), color: colors.textPrimary)),
          ])),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Perkembangan saldo', action: '30 hari'),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rupiah(balance), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.textPrimary)),
            const SizedBox(height: 12),
            SizedBox(height: 62, child: CustomPaint(painter: SparklinePainter(color: colors.accent))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('01 Agu', style: TextStyle(color: colors.textMuted, fontSize: 10)),
              Text('10 Agu', style: TextStyle(color: colors.textMuted, fontSize: 10)),
              Text('20 Agu', style: TextStyle(color: colors.textMuted, fontSize: 10)),
              Text('Hari ini', style: TextStyle(color: colors.textMuted, fontSize: 10)),
            ]),
          ])),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Transaksi terbaru', action: 'Lihat semua'),
          SurfaceCard(child: Column(children: items.take(4).map((e) => TransactionRow(item: e)).toList())),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Target tabungan', action: 'Kelola'),
          SurfaceCard(color: colors.surfaceAlt, child: Row(children: [
            CircleAvatar(backgroundColor: colors.positive.withOpacity(0.18), child: Icon(Icons.wb_sunny_outlined, color: colors.positive)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Dana liburan', style: TextStyle(fontWeight: FontWeight.w700, color: colors.textPrimary)),
                Text('35%', style: TextStyle(color: colors.positive, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 5),
              Text('Rp 4.200.000 dari Rp 12.000.000', style: TextStyle(color: colors.textMuted, fontSize: 11)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: .35, minHeight: 6, backgroundColor: colors.border, color: colors.positive),
              ),
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
    final colors = context.colors;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Transaksi', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: colors.textPrimary)),
        const SizedBox(height: 6),
        Text('Semua aktivitas keuanganmu', style: TextStyle(color: colors.textMuted)),
        const SizedBox(height: 20),
        TextField(
          decoration: InputDecoration(
            hintText: 'Cari transaksi',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: colors.border)),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: ['Semua', 'Pemasukan', 'Pengeluaran'].map((e) => Chip(
          label: Text(e),
          backgroundColor: e == 'Semua' ? colors.accent : colors.surface,
          labelStyle: TextStyle(color: e == 'Semua' ? colors.onAccent : colors.textPrimary),
          side: BorderSide(color: colors.border),
        )).toList()),
        const SizedBox(height: 18),
        SurfaceCard(child: Column(children: items.map((e) => TransactionRow(item: e)).toList())),
      ]),
    );
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(transactionsProvider);
    final colors = context.colors;
    final expense = items.where((e) => !e.income).fold<double>(0, (s, e) => s + e.amount);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Laporan', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: colors.textPrimary)),
        const SizedBox(height: 6),
        Text('Lihat pola keuanganmu', style: TextStyle(color: colors.textMuted)),
        const SizedBox(height: 22),
        SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pengeluaran bulan ini', style: TextStyle(color: colors.textMuted)),
          const SizedBox(height: 7),
          Text(rupiah(expense), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colors.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(height: 145, child: CustomPaint(painter: BarChartPainter(primary: colors.accent, secondary: colors.positive))),
        ])),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Kategori terbesar', action: 'Bulan ini'),
        SurfaceCard(child: Column(children: [
          ReportLine(label: 'Belanja', amount: 'Rp 680.000', percent: '57%', color: colors.accent),
          ReportLine(label: 'Transportasi', amount: 'Rp 120.000', percent: '10%', color: colors.positive),
          ReportLine(label: 'Makanan', amount: 'Rp 45.000', percent: '4%', color: const Color(0xFF9B8AFB)),
        ])),
      ]),
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Profil', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: colors.textPrimary)),
          const SizedBox(height: 22),
          SurfaceCard(child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: accent, child: Text('R', style: TextStyle(color: colors.onAccent, fontSize: 24, fontWeight: FontWeight.w900))),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Raka', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.textPrimary)),
              const SizedBox(height: 4),
              Text('Kelola profil dan preferensi', style: TextStyle(color: colors.textMuted, fontSize: 12)),
            ]),
          ])),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Tampilan'),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tema', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.textPrimary)),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Terang')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Gelap')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.smartphone_outlined), label: Text('Sistem')),
              ],
              selected: {themeMode},
              onSelectionChanged: (value) => ref.read(themeModeProvider.notifier).state = value.first,
            ),
            const SizedBox(height: 22),
            Text('Warna aksen', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: accentPresets.map((color) {
              final selected = color.value == accent.value;
              return GestureDetector(
                onTap: () => ref.read(accentColorProvider.notifier).state = color,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? colors.textPrimary : Colors.transparent, width: 2.5),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 18, color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87)
                      : null,
                ),
              );
            }).toList()),
          ])),
          const SizedBox(height: 20),
          SurfaceCard(child: Column(children: const [
            SettingRow(icon: Icons.account_balance_wallet_outlined, title: 'Saldo awal', value: 'Rp 2.500.000'),
            SettingRow(icon: Icons.category_outlined, title: 'Kelola kategori'),
            SettingRow(icon: Icons.currency_exchange, title: 'Mata uang', value: 'Rupiah (IDR)'),
          ])),
        ],
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color iconColor;
  final VoidCallback onTap;
  const ActionTile({super.key, required this.label, required this.icon, required this.background, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.border)),
        child: Row(children: [
          CircleAvatar(radius: 17, backgroundColor: iconColor.withOpacity(0.16), child: Icon(icon, size: 19, color: iconColor)),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: colors.textPrimary))),
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        if (action != null) Text(action!, style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  const SurfaceCard({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class SummaryValue extends StatelessWidget {
  final String label, value;
  final Color color;
  const SummaryValue({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      const SizedBox(height: 7),
      Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
    ]);
  }
}

class TransactionRow extends StatelessWidget {
  final FinanceTransaction item;
  const TransactionRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = item.income ? colors.positive : colors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: tint.withOpacity(0.16),
          child: Icon(item.income ? Icons.arrow_downward : Icons.shopping_bag_outlined, size: 18, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: colors.textPrimary)),
          const SizedBox(height: 4),
          Text('${item.category} · ${DateFormat('dd MMM yyyy').format(item.date)}', style: TextStyle(color: colors.textMuted, fontSize: 11)),
        ])),
        Text('${item.income ? '+' : '-'}${rupiah(item.amount)}', style: TextStyle(color: item.income ? colors.positive : colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class ReportLine extends StatelessWidget {
  final String label, amount, percent;
  final Color color;
  const ReportLine({super.key, required this.label, required this.amount, required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: colors.textPrimary))),
        Text(amount, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: colors.textPrimary)),
        const SizedBox(width: 12),
        Text(percent, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      ]),
    );
  }
}

class SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  const SettingRow({super.key, required this.icon, required this.title, this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colors.accent),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
      trailing: value != null
          ? Text(value!, style: TextStyle(color: colors.textMuted, fontSize: 12))
          : Icon(Icons.chevron_right, color: colors.textMuted),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final Color color;
  const SparklinePainter({required this.color});

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, s.height * .78)
      ..lineTo(s.width * .58, s.height * .46)
      ..lineTo(s.width * .72, s.height * .53)
      ..lineTo(s.width, s.height * .18);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) => oldDelegate.color != color;
}

class BarChartPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  const BarChartPainter({required this.primary, required this.secondary});

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..strokeWidth = 18..strokeCap = StrokeCap.round;
    final values = [0.46, 0.74, 0.34, 0.9, 0.58, 0.7, 0.43];
    for (var i = 0; i < values.length; i++) {
      p.color = i.isEven ? primary : secondary;
      final x = 18.0 + i * (s.width - 36) / 6;
      c.drawLine(Offset(x, s.height), Offset(x, s.height * (1 - values[i])), p);
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

String rupiah(double value) => 'Rp ${NumberFormat('#,###', 'id_ID').format(value).replaceAll(',', '.')}';

Future<void> showTransactionDialog(BuildContext context, WidgetRef ref, bool income) async {
  final title = TextEditingController();
  final amount = TextEditingController();
  final colors = context.colors;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tambah ${income ? 'pemasukan' : 'pengeluaran'}', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colors.textPrimary)),
        const SizedBox(height: 20),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ')),
        const SizedBox(height: 12),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final value = double.tryParse(amount.text.replaceAll('.', '')) ?? 0;
              if (title.text.isNotEmpty && value > 0) {
                ref.read(transactionsProvider.notifier).add(title.text, value, income);
                Navigator.pop(context);
              }
            },
            child: const Text('Simpan transaksi'),
          ),
        ),
      ]),
    ),
  );
}
