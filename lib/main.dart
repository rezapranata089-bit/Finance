import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MyFinanceApp(),
  ));
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final transactionsProvider = StateNotifierProvider<TransactionController,
    List<FinanceTransaction>>((ref) => TransactionController());

final selectedTabProvider = StateProvider<int>((ref) => 0);

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(sharedPreferencesProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences prefs;
  ThemeModeNotifier(this.prefs) : super(_load(prefs));

  static ThemeMode _load(SharedPreferences prefs) {
    final val = prefs.getString('themeMode') ?? 'dark';
    return ThemeMode.values.firstWhere((e) => e.name == val, orElse: () => ThemeMode.dark);
  }

  void updateTheme(ThemeMode mode) {
    state = mode;
    prefs.setString('themeMode', mode.name);
  }
}

final accentColorProvider = StateNotifierProvider<AccentColorNotifier, Color>((ref) {
  return AccentColorNotifier(ref.watch(sharedPreferencesProvider));
});

class AccentColorNotifier extends StateNotifier<Color> {
  final SharedPreferences prefs;
  AccentColorNotifier(this.prefs) : super(_load(prefs));

  static Color _load(SharedPreferences prefs) {
    final val = prefs.getInt('accentColor');
    return val != null ? Color(val) : accentPresets.first;
  }

  void updateColor(Color color) {
    state = color;
    prefs.setInt('accentColor', color.value);
  }
}

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
      background: const Color(0xFF0F1115),
      surface: const Color(0xFF181B21),
      surfaceAlt: const Color(0xFF22262E),
      border: Colors.transparent,
      textPrimary: const Color(0xFFF1F3F5),
      textMuted: const Color(0xFF8B929D),
      positive: const Color(0xFF4ADE80),
    );
  }
  return AppColors(
    accent: accent,
    onAccent: onAccent,
    background: const Color(0xFFF4F6F8),
    surface: Colors.white,
    surfaceAlt: const Color(0xFFEEF0F4),
    border: Colors.transparent,
    textPrimary: const Color(0xFF1A1D21),
    textMuted: const Color(0xFF6B7280),
    positive: const Color(0xFF10B981),
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
    textTheme: base.textTheme.apply(fontFamily: 'Satoshi'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Satoshi'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddTransactionChoice(context, ref),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) =>
            ref.read(selectedTabProvider.notifier).state = index,
        backgroundColor: colors.surface,
        indicatorColor: colors.accent.withOpacity(0.18),
        destinations: const [
          NavigationDestination(icon: Icon(SolarIconsOutline.home), selectedIcon: Icon(SolarIconsBold.home), label: 'Dashboard'),
          NavigationDestination(icon: Icon(SolarIconsOutline.billList), selectedIcon: Icon(SolarIconsBold.billList), label: 'Transaksi'),
          NavigationDestination(icon: Icon(SolarIconsOutline.chartSquare), selectedIcon: Icon(SolarIconsBold.chartSquare), label: 'Laporan'),
          NavigationDestination(icon: Icon(SolarIconsOutline.user), selectedIcon: Icon(SolarIconsBold.user), label: 'Profil'),
        ],
      ),
    );
  }
}

class DashboardSwiper extends StatefulWidget {
  final double income;
  final double expense;
  const DashboardSwiper({super.key, required this.income, required this.expense});

  @override
  State<DashboardSwiper> createState() => _DashboardSwiperState();
}

class _DashboardSwiperState extends State<DashboardSwiper> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  double _currentPage = 10000.0;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    // KUNCI UTAMA 1: viewportFraction 0.68 agar jarak titik tengah antar-kartu lebih sempit.
    // initialPage 10000 agar pengguna dapat melakukan Infinite Swipe/Loop ke kiri dan kanan.
    _pageController = PageController(viewportFraction: 0.68, initialPage: 10000);
    _pageController.addListener(() {
      if (_pageController.page != null) {
        setState(() {
          _currentPage = _pageController.page!;
        });
      }
    });
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            clipBehavior: Clip.none, // Mencegah kartu samping yang mengintip ikut terpotong
            itemBuilder: (context, index) {
              double value = _currentPage - index;
              double absValue = value.abs().clamp(0.0, 1.0);
              
              // 1. Skala card di samping menyusut sekitar 12%
              double scale = 1.0 - (absValue * 0.12);
              
              // 2. Mendorong card di samping turun sedikit ke bawah (Efek melengkung)
              double translateY = absValue * 22.0; 
              
              // 3. Putaran kipas 3D miring ke luar
              double rotateZ = value * -5 * math.pi / 180; 
              
              // 4. Translasi menarik rapat sedikit ke dalam agar card samping masuk ke belakang card utama
              double translateX = value * 15.0; 
              
              // 5. Card samping sedikit lebih transparan
              double opacity = 1.0 - (absValue * 0.4);

              return OverflowBox(
                // KUNCI UTAMA 2: Mengabaikan perintah PageView (0.68) dan memaksa
                // lebar fisik tiap kartu untuk mengisi 88% layar. Ini yang membuat
                // kartu saling menumpuk/overlap satu sama lain dengan presisi.
                maxWidth: MediaQuery.of(context).size.width * 0.88,
                maxHeight: 250.0,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(translateX, translateY, 0.0)
                    ..rotateZ(rotateZ)
                    ..scale(scale),
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: opacity,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: 190.0, // Kunci tinggi card statis persis dengan desain CSS/HTML
                        child: _buildCard(index % 3, absValue < 0.3),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            // Kalkulasi Index Loop (10000 % 3)
            double diff = (_currentPage % 3 - index).abs();
            if (diff > 1.5) diff = 3 - diff; // Menyambungkan jarak loop terakhir
            
            bool isActive = diff < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 14 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFC96343) : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(99),
                boxShadow: isActive ? [BoxShadow(color: const Color(0xFFC96343).withOpacity(0.4), blurRadius: 8)] : null,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCard(int index, bool isActive) {
    if (index == 0) {
      return _CardBase(
        isActive: isActive,
        animController: _animController,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1D16), Color(0xFF1A1410), Color(0xFF140E0A)],
        ),
        glowColor: const Color(0xFFE4A98A).withOpacity(0.3),
        glowAlign: Alignment.bottomLeft,
        title: 'TOTAL STOK BATU',
        amount: '15.000',
        subLabel: 'Modal Bakar',
        subValue: 'Rp 4.500.000',
        btnText: 'Lihat Detail',
        statLabel: 'Status',
        statValue: 'Standby',
        statColor: const Color(0xFFFFE270),
        amountGradient: const [Color(0xFFC9BC75), Colors.white, Color(0xFFC9BC75)],
      );
    }
    if (index == 1) {
      return _CardBase(
        isActive: isActive,
        animController: _animController,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A120D), Color(0xFF152016), Color(0xFF080A08)],
        ),
        glowColor: const Color(0xFF5CC88F).withOpacity(0.3),
        glowAlign: Alignment.bottomLeft,
        title: 'KEUNTUNGAN BERSIH',
        amount: NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(widget.income),
        subLabel: 'Sisa Modal Usaha',
        subValue: 'Rp 12.000.000',
        btnText: 'Tarik Dana',
        statLabel: 'Pertumbuhan',
        statValue: '+24.5%',
        statColor: const Color(0xFF5CC88F),
        amountGradient: const [Color(0xFF5CC88F), Color(0xFFD4FADF), Color(0xFF5CC88F)],
      );
    }
    return _CardBase(
      isActive: isActive,
      animController: _animController,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF240C0C), Color(0xFF3D1515), Color(0xFF170505)],
      ),
      glowColor: const Color(0xFFEB5757).withOpacity(0.3),
      glowAlign: Alignment.bottomRight,
      title: 'TOTAL PENGELUARAN',
      amount: NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(widget.expense),
      subLabel: 'Bulan Ini',
      subValue: 'Kayu Bakar & Gaji',
      btnText: 'Cek Laporan',
      statLabel: 'Beban',
      statValue: '-12%',
      statColor: const Color(0xFFEB5757),
      amountGradient: const [Color(0xFFEB5757), Color(0xFFFAD4D4), Color(0xFFEB5757)],
    );
  }
}

class _CardBase extends StatelessWidget {
  final bool isActive;
  final AnimationController animController;
  final Gradient gradient;
  final Color glowColor;
  final Alignment glowAlign;
  final String title;
  final String amount;
  final String subLabel;
  final String subValue;
  final String btnText;
  final String statLabel;
  final String statValue;
  final Color statColor;
  final List<Color> amountGradient;

  const _CardBase({
    required this.isActive,
    required this.animController,
    required this.gradient,
    required this.glowColor,
    required this.glowAlign,
    required this.title,
    required this.amount,
    required this.subLabel,
    required this.subValue,
    required this.btnText,
    required this.statLabel,
    required this.statValue,
    required this.statColor,
    required this.amountGradient,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuad,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: isActive
            ? [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 48, offset: const Offset(0, 24)),
              ]
            : [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            if (isActive)
              Positioned(
                bottom: -80,
                left: glowAlign == Alignment.bottomLeft ? -40 : null,
                right: glowAlign == Alignment.bottomRight ? -40 : null,
                child: AnimatedBuilder(
                  animation: animController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (animController.value * 0.1),
                      child: Opacity(
                        opacity: 0.5 + (animController.value * 0.3),
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [glowColor, Colors.transparent],
                              stops: const [0.0, 0.6],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.55),
                          letterSpacing: 1.2,
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFe8c97a), Color(0xFFc9a85c), Color(0xFFa07840)],
                          ),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 14,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Center(
                              child: Container(
                                width: 1,
                                color: Colors.black.withOpacity(0.25),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: amountGradient,
                          stops: const [0.0, 0.5, 1.0],
                          transform: isActive
                              ? GradientRotation(animController.value * 2 * math.pi)
                              : null,
                        ).createShader(bounds),
                        child: Text(
                          amount,
                          style: const TextStyle(
                            fontFamily: 'Playfair Display',
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            subLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.45),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            subValue,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Text(
                          btnText,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            statLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withOpacity(0.4),
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statValue,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: statColor,
                              shadows: [BoxShadow(color: statColor.withOpacity(0.4), blurRadius: 12)],
                            ),
                          ),
                        ],
                      )
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
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
    
    // Helper untuk mengembalikan padding ke elemen di luar Swiper
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 28),
        clipBehavior: Clip.none,
        children: [
          pad(Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MINGGU, 23 AGUSTUS', style: TextStyle(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
              const SizedBox(height: 6),
              Text('Selamat pagi, Andi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            ])),
            IconButton.filledTonal(onPressed: () {}, icon: const Icon(SolarIconsOutline.bell)),
          ])),
          const SizedBox(height: 22),
          // Swiper tidak di-padding agar bisa bebas mengambil ruang kiri-kanan layar penuh
          SizedBox(
            height: 230,
            child: DashboardSwiper(income: income, expense: expense),
          ),
          const SizedBox(height: 36),
          pad(const SectionHeader(title: 'Ringkasan bulan ini', action: 'Detail')),
          pad(SurfaceCard(child: Row(children: [
            Expanded(child: SummaryValue(label: 'Pemasukan', value: rupiah(income), color: colors.positive)),
            const SizedBox(width: 18), Container(width: 1, height: 53, color: colors.textMuted.withOpacity(0.2)), const SizedBox(width: 18),
            Expanded(child: SummaryValue(label: 'Pengeluaran', value: rupiah(expense), color: colors.textPrimary)),
          ]))),
          const SizedBox(height: 36),
          pad(const SectionHeader(title: 'Transaksi terbaru', action: 'Lihat semua')),
          pad(SurfaceCard(child: Column(children: items.take(4).map((e) => TransactionRow(item: e)).toList()))),
          const SizedBox(height: 36),
          pad(const SectionHeader(title: 'Target tabungan', action: 'Kelola')),
          pad(SurfaceCard(color: colors.surfaceAlt, child: Row(children: [
            CircleAvatar(backgroundColor: colors.positive.withOpacity(0.18), child: Icon(SolarIconsOutline.sun, color: colors.positive)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Dana liburan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: colors.textPrimary)),
                Text('35%', style: TextStyle(color: colors.positive, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Text('Rp 4.200.000 dari Rp 12.000.000', style: TextStyle(color: colors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: .35, minHeight: 8, backgroundColor: colors.textMuted.withOpacity(0.2), color: colors.positive),
              ),
            ])),
          ]))),
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
        Text('Transaksi', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        const SizedBox(height: 8),
        Text('Semua aktivitas keuanganmu', style: TextStyle(color: colors.textMuted)),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.light ? 0.05 : 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Cari transaksi',
              prefixIcon: const Icon(SolarIconsOutline.magnifier),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(spacing: 8, children: ['Semua', 'Pemasukan', 'Pengeluaran'].map((e) => Chip(
          label: Text(e),
          backgroundColor: e == 'Semua' ? colors.accent : colors.surface,
          labelStyle: TextStyle(color: e == 'Semua' ? colors.onAccent : colors.textPrimary, fontWeight: FontWeight.w600),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        )).toList()),
        const SizedBox(height: 32),
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
        Text('Laporan', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: colors.textPrimary)),
        const SizedBox(height: 8),
        Text('Lihat pola keuanganmu', style: TextStyle(color: colors.textMuted)),
        const SizedBox(height: 32),
        SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pengeluaran bulan ini', style: TextStyle(color: colors.textMuted)),
          const SizedBox(height: 7),
          Text(rupiah(expense), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(height: 145, width: double.infinity, child: CustomPaint(painter: BarChartPainter(primary: colors.accent, secondary: colors.positive))),
        ])),
                const SizedBox(height: 36),
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
          Text('Profil', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          const SizedBox(height: 32),
          SurfaceCard(child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: accent, child: Text('R', style: TextStyle(color: colors.onAccent, fontSize: 24, fontWeight: FontWeight.w700))),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Raka', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const SizedBox(height: 4),
              Text('Kelola profil dan preferensi', style: TextStyle(color: colors.textMuted, fontSize: 13)),
            ]),
          ])),
                    const SizedBox(height: 36),
                    const SectionHeader(title: 'Tampilan'),
                    SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Tema', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.textPrimary)),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(SolarIconsOutline.sun), label: Text('Terang')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(SolarIconsOutline.moon), label: Text('Gelap')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(SolarIconsOutline.smartphone), label: Text('Sistem')),
              ],
              selected: {themeMode},
              onSelectionChanged: (value) => ref.read(themeModeProvider.notifier).updateTheme(value.first),
            ),
            const SizedBox(height: 22),
            Text('Warna aksen', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: accentPresets.map((color) {
              final selected = color.value == accent.value;
              return GestureDetector(
                onTap: () => ref.read(accentColorProvider.notifier).updateColor(color),
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
          const SizedBox(height: 36),
          SurfaceCard(child: Column(children: const [
            SettingRow(icon: SolarIconsOutline.wallet, title: 'Saldo awal', value: 'Rp 2.500.000'),
            SettingRow(icon: SolarIconsOutline.widget, title: 'Kelola kategori'),
            SettingRow(icon: SolarIconsOutline.cardTransfer, title: 'Mata uang', value: 'Rupiah (IDR)'),
          ])),
        ],
      ),
    );
  }
}

class _CardData {
  final String title;
  final double amount;
  final bool isIncome;
  _CardData(this.title, this.amount, this.isIncome);
}

class DashboardCards extends StatefulWidget {
  final double income;
  final double expense;
  const DashboardCards({super.key, required this.income, required this.expense});

  @override
  State<DashboardCards> createState() => _DashboardCardsState();
}

class _DashboardCardsState extends State<DashboardCards> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _shimmerController;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pageController = PageController(viewportFraction: 1.0);
    _pageController.addListener(_handlePageChange);
  }

  void _handlePageChange() {
    if (!mounted || !_pageController.position.haveDimensions) return;
    final rounded = _pageController.page!.round();
    if (rounded != _activeIndex) {
      setState(() => _activeIndex = rounded);
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_handlePageChange);
    _shimmerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cards = [
      _CardData('TOTAL PEMASUKAN', widget.income, true),
      _CardData('TOTAL PENGELUARAN', widget.expense, false),
    ];

    return Column(
      children: [
        SizedBox(
          height: 185,
          child: PageView.builder(
            clipBehavior: Clip.none,
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final data = cards[index];
              final isActive = index == _activeIndex;
              final cardChild = RepaintBoundary(
                child: _buildCard(context, data, colors, isActive),
              );

              return AnimatedBuilder(
                animation: _pageController,
                child: cardChild,
                builder: (context, child) {
                  double scale = 1.0;
                  double opacity = 1.0;
                  if (_pageController.position.haveDimensions) {
                    final diff = _pageController.page! - index;
                    scale = (1 - (diff.abs() * 0.1)).clamp(0.9, 1.0);
                    opacity = (1 - (diff.abs() * 0.4)).clamp(0.0, 1.0);
                  }
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _pageController,
          builder: (context, _) {
            final page = _pageController.position.haveDimensions
                ? (_pageController.page ?? _activeIndex.toDouble())
                : _activeIndex.toDouble();
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cards.length, (index) {
                final selected = page.round() == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? colors.accent : colors.textMuted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, _CardData data, AppColors colors, bool isActive) {
    final isExpense = !data.isIncome;
    final trendColor = isExpense ? const Color(0xFFEB5757) : const Color(0xFF5CC88F);
    final trendIcon = isExpense ? SolarIconsOutline.graphDown : SolarIconsOutline.graphUp;
    final trendText = isExpense ? '-3.2%' : '+8.4%';
    
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColors = isExpense 
        ? (isLight 
            ? const [Color(0xFF3B1010), Color(0xFF541717), Color(0xFF240909)]
            : const [Color(0xFF240C0C), Color(0xFF3D1515), Color(0xFF170505)])
        : (isLight 
            ? const [Color(0xFF0E2815), Color(0xFF143B20), Color(0xFF08170D)]
            : const [Color(0xFF0A120D), Color(0xFF152016), Color(0xFF080A08)]);
            
    final patternColor = isExpense
        ? const Color.fromRGBO(235, 87, 87, 0.04)
        : const Color.fromRGBO(92, 200, 143, 0.04);
    
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.light ? 0.1 : 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CardPatternPainter(patternColor: patternColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(data.title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12, letterSpacing: 1.2)),
                Opacity(
                  opacity: 0.9,
                  child: Container(
                    width: 32,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE8C97A), Color(0xFFC9A85C), Color(0xFFA07840)],
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 32 * 0.7,
                        height: 24 * 0.7,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black38, width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Center(
                          child: Container(width: 1, color: Colors.black26),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _buildAmount(isExpense, isActive, data.amount),
              const Spacer(),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: trendColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(trendIcon, size: 14, color: trendColor),
                    const SizedBox(width: 6),
                    Text(trendText, style: TextStyle(color: trendColor, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(width: 10),
                const Text(
                  'dibanding bulan lalu',
                  style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildAmount(bool isExpense, bool isActive, double amount) {
    final baseStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 36,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.42,
      height: 1.4,
      fontFeatures: const [
        FontFeature.enable('lnum'),
        FontFeature.enable('tnum'),
      ],
    );
    final themeColor = isExpense ? const Color(0xFFEB5757) : const Color(0xFF5CC88F);
    final text = rupiah(amount);

    final glyphs = isActive
        ? AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: isExpense
                      ? const [Color(0xFFEB5757), Color(0xFFFAD4D4), Color(0xFFEB5757)]
                      : const [Color(0xFF5CC88F), Color(0xFFD4FADF), Color(0xFF5CC88F)],
                  stops: const [0.35, 0.5, 0.65],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: _SlidingGradientTransform(
                    slidePercent: -1.5 + (_shimmerController.value * 3.0),
                  ),
                ).createShader(bounds),
                child: child,
              );
            },
            child: Text(text, style: baseStyle.copyWith(color: Colors.white)),
          )
        : Text(text, style: baseStyle.copyWith(color: themeColor));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 3,
          left: 0,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Text(
              text,
              style: baseStyle.copyWith(color: themeColor.withOpacity(0.35)),
            ),
          ),
        ),
        glyphs,
      ],
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLight ? 0.05 : 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(children: [
          CircleAvatar(radius: 17, backgroundColor: iconColor.withOpacity(0.16), child: Icon(icon, size: 19, color: iconColor)),
          const SizedBox(width: 12),
          Flexible(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary))),
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400, color: colors.textPrimary, fontFamily: 'DM Serif Display')),
        if (action != null) Text(action!, style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.05 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
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
      Text(label, style: TextStyle(color: colors.textMuted, fontSize: 13)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
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
          child: Icon(item.income ? SolarIconsOutline.arrowDown : SolarIconsOutline.bag, size: 18, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: colors.textPrimary)),
          const SizedBox(height: 6),
          Text('${item.category} · ${DateFormat('dd MMM yyyy').format(item.date)}', style: TextStyle(color: colors.textMuted, fontSize: 12)),
        ])),
        Text('${item.income ? '+' : '-'}${rupiah(item.amount)}', style: TextStyle(color: item.income ? colors.positive : colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500))),
        Text(amount, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: colors.textPrimary)),
        const SizedBox(width: 16),
        Text(percent, style: TextStyle(color: colors.textMuted, fontSize: 14)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: colors.accent.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: colors.accent, size: 20),
        ),
        title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colors.textPrimary)),
        trailing: value != null
            ? Text(value!, style: TextStyle(color: colors.textMuted, fontSize: 13))
            : Icon(SolarIconsOutline.altArrowRight, color: colors.textMuted, size: 18),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

class CardPatternPainter extends CustomPainter {
  final Color patternColor;
  const CardPatternPainter({required this.patternColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = patternColor
      ..style = PaintingStyle.fill;
      
    final path1 = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.4)
      ..cubicTo(
        size.width * 0.375, size.height * 0.8,
        size.width * 0.625, -size.height * 0.1,
        size.width, size.height * 0.5,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path1, paint1);

    final paint2 = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.02)
      ..style = PaintingStyle.fill;
      
    final path2 = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.65)
      ..cubicTo(
        size.width * 0.3, size.height * 0.9,
        size.width * 0.75, size.height * 0.25,
        size.width, size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CardPatternPainter oldDelegate) => oldDelegate.patternColor != patternColor;
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

Future<void> showAddTransactionChoice(BuildContext context, WidgetRef ref) async {
  final colors = context.colors;
  await showModalBottomSheet(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Tambah transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colors.textPrimary)),
          const SizedBox(height: 18),
          ListTile(
            leading: CircleAvatar(backgroundColor: colors.positive.withOpacity(0.16), child: Icon(Icons.arrow_downward, color: colors.positive)),
            title: Text('Pemasukan', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              showTransactionDialog(context, ref, true);
            },
          ),
          ListTile(
            leading: CircleAvatar(backgroundColor: colors.accent.withOpacity(0.16), child: Icon(Icons.arrow_upward, color: colors.accent)),
            title: Text('Pengeluaran', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              showTransactionDialog(context, ref, false);
            },
          ),
        ]),
      ),
    ),
  );
}

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
