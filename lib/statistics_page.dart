// ============================================================
// TAB STATISTIK — REDESIGN
// Terinspirasi dari desain "Tab Analitik" (chart tren kumulatif +
// toggle Hari/Bulan/Tahun + strip pemilih titik + kartu ringkasan
// dengan target budget), tapi seluruh warna/kartu di sini memakai
// palet & komponen yang sudah dipakai app (LiquidGlass, GlassSegmented
// Control, NumberFlow, context.cardColor dkk) supaya menyatu dengan
// tema terang/gelap app — bukan hardcode warna gelap ala web aslinya.
//
// Header (judul + selector kartu) SENGAJA tidak meniru desain aslinya
// dan memakai gaya header yang sama seperti halaman lain di app.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:number_flow_flutter/number_flow_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

// ===== WARNA (dipilih dari palet warna yang SUDAH ada di app, lihat
// _customPalettes di main.dart, supaya benar-benar menyatu dengan tema) =====
const Color _colorPositive = Color(0xFF24A148); // sama dengan warna income di app
const Color _colorNegative = Color(0xFFE05270); // sama dengan warna expense di app
const Color _colorInterest = Color(0xFF7655D8); // Lavender Glow (palet app)
const Color _colorLoan = Color(0xFFD4AF37); // emas, penanda "Pinjaman"
const Color _colorRepay = Color(0xFF2196F3); // Ocean Breeze (palet app)

String _l(AppLang lang, String id, String en) => lang == AppLang.id ? id : en;

// ============================================================
// MODE & FOKUS PERIODE
// ============================================================
enum StatsMode { day, month, year }

final statsModeProvider = StateProvider<StatsMode>((ref) => StatsMode.day);

final statsFocusProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

// Kunci global tunggal untuk chart tren statistik: dipakai Listener
// pembungkus halaman ini untuk memeriksa apakah tekanan jari berada di
// dalam area grafik (termasuk strip hari) atau di luar, tanpa perlu
// mengubah StatisticsPage jadi StatefulWidget. Aman sebagai variabel
// tingkat modul karena hanya ada SATU instance tab Statistik yang aktif
// (semua tab di FinanceShell dibangun sekaligus lewat PageView).
final GlobalKey<_TrendHeroChartState> _statsChartKey = GlobalKey<_TrendHeroChartState>();

// Menyembunyikan tooltip chart tren secara langsung saat pengguna menekan
// di luar area grafik — termasuk saat menekan tombol/kontrol lain di tab
// ini — sesuai permintaan agar tooltip tidak terus menempel di layar.
void _handleStatsPointerDown(PointerDownEvent event) {
  final renderObject = _statsChartKey.currentContext?.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) {
    _statsChartKey.currentState?.clearSelection();
    return;
  }
  final local = renderObject.globalToLocal(event.position);
  final inside = local.dx >= 0 && local.dy >= 0 && local.dx <= renderObject.size.width && local.dy <= renderObject.size.height;
  if (!inside) {
    _statsChartKey.currentState?.clearSelection();
  }
}

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

// ============================================================
// TARGET / BUDGET BULANAN (disimpan lokal via SharedPreferences,
// mengikuti pola CardsNotifier/CustomCategoriesNotifier di main.dart)
// ============================================================
class StatsBudget {
  final double targetSave;
  final double limitSpend;
  const StatsBudget({this.targetSave = 0, this.limitSpend = 0});

  Map<String, dynamic> toJson() => {'targetSave': targetSave, 'limitSpend': limitSpend};

  factory StatsBudget.fromJson(Map<String, dynamic> json) => StatsBudget(
        targetSave: (json['targetSave'] as num?)?.toDouble() ?? 0,
        limitSpend: (json['limitSpend'] as num?)?.toDouble() ?? 0,
      );
}

class StatsBudgetsNotifier extends StateNotifier<Map<String, StatsBudget>> {
  final SharedPreferences prefs;
  static const _key = 'stats_budgets';

  StatsBudgetsNotifier(this.prefs) : super(_load(prefs));

  static Map<String, StatsBudget> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, StatsBudget.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  void _persist() {
    prefs.setString(_key, jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))));
  }

  void setBudget(String monthKey, {required double targetSave, required double limitSpend}) {
    state = {...state, monthKey: StatsBudget(targetSave: targetSave, limitSpend: limitSpend)};
    _persist();
  }
}

final statsBudgetsProvider = StateNotifierProvider<StatsBudgetsNotifier, Map<String, StatsBudget>>(
  (ref) => StatsBudgetsNotifier(ref.watch(prefsProvider)),
);

// ============================================================
// KLASIFIKASI TRANSAKSI (dipetakan dari kategori yang SUDAH ada
// di FinanceTransaction/Loan main.dart — tidak menambah kategori baru)
// ============================================================
enum _TxCat { saving, spend, bunga, pinjaman, lunas }
enum DomCat { none, saving, spend, bunga, pinjaman, lunas }

_TxCat _classify(FinanceTransaction t) {
  if (t.category == 'Bunga Pinjaman') return _TxCat.bunga;
  if (t.category == 'Pinjaman Diberikan') return _TxCat.pinjaman;
  if (t.category == 'Cicilan Pokok') return _TxCat.lunas;
  return t.income ? _TxCat.saving : _TxCat.spend;
}

Color _colorForDomCat(DomCat cat) {
  switch (cat) {
    case DomCat.saving:
      return _colorPositive;
    case DomCat.spend:
      return _colorNegative;
    case DomCat.bunga:
      return _colorInterest;
    case DomCat.pinjaman:
      return _colorLoan;
    case DomCat.lunas:
      return _colorRepay;
    case DomCat.none:
      return Colors.grey;
  }
}

class _Bucket {
  double saving = 0, spend = 0, bunga = 0, pinjaman = 0, lunas = 0;
  double signedTotal = 0;
  bool hasTx = false;

  void add(FinanceTransaction t) {
    hasTx = true;
    signedTotal += t.income ? t.amount : -t.amount;
    switch (_classify(t)) {
      case _TxCat.saving:
        saving += t.amount;
        break;
      case _TxCat.spend:
        spend += t.amount;
        break;
      case _TxCat.bunga:
        bunga += t.amount;
        break;
      case _TxCat.pinjaman:
        pinjaman += t.amount;
        break;
      case _TxCat.lunas:
        lunas += t.amount;
        break;
    }
  }

  DomCat get domCat {
    if (!hasTx) return DomCat.none;
    final maxVal = [saving, spend, bunga, pinjaman, lunas].reduce((a, b) => a > b ? a : b);
    if (pinjaman > 0 && maxVal == pinjaman) return DomCat.pinjaman;
    if (lunas > 0 && maxVal == lunas) return DomCat.lunas;
    if (maxVal == saving) return DomCat.saving;
    if (maxVal == spend) return DomCat.spend;
    return DomCat.bunga;
  }
}

// ============================================================
// TITIK DATA CHART (nilai kumulatif berjalan, mengikuti pola
// "running total" pada desain aslinya)
// ============================================================
class StatsPoint {
  final String label;
  final String sub;
  final double value;
  final double rawValue;
  final bool hasTx;
  final bool isToday;
  final DomCat domCat;
  final double savingAmt;
  final double spendAmt;
  final double bungaAmt;
  final double pinjamanAmt;
  final double lunasAmt;

  const StatsPoint({
    required this.label,
    required this.sub,
    required this.value,
    required this.rawValue,
    required this.hasTx,
    required this.isToday,
    required this.domCat,
    required this.savingAmt,
    required this.spendAmt,
    required this.bungaAmt,
    required this.pinjamanAmt,
    required this.lunasAmt,
  });
}

List<StatsPoint> _buildPoints(StatsMode mode, DateTime focus, List<FinanceTransaction> data, AppLang lang) {
  switch (mode) {
    case StatsMode.day:
      return _buildDayPoints(focus, data, lang);
    case StatsMode.month:
      return _buildMonthPoints(focus, data, lang);
    case StatsMode.year:
      return _buildYearPoints(focus, data);
  }
}

List<StatsPoint> _buildDayPoints(DateTime focus, List<FinanceTransaction> data, AppLang lang) {
  final dayNames = lang == AppLang.id
      ? const ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab']
      : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final year = focus.year, month = focus.month;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final buckets = List.generate(daysInMonth, (_) => _Bucket());
  for (final t in data) {
    if (t.date.year == year && t.date.month == month) {
      final idx = t.date.day - 1;
      if (idx >= 0 && idx < daysInMonth) buckets[idx].add(t);
    }
  }
  final today = DateTime.now();
  double running = 0;
  final points = <StatsPoint>[];
  for (var i = 0; i < daysInMonth; i++) {
    final b = buckets[i];
    running += b.signedTotal;
    final dateObj = DateTime(year, month, i + 1);
    points.add(StatsPoint(
      label: '${i + 1}',
      sub: dayNames[dateObj.weekday % 7],
      value: running,
      rawValue: b.signedTotal,
      hasTx: b.hasTx,
      isToday: dateObj.year == today.year && dateObj.month == today.month && dateObj.day == today.day,
      domCat: b.domCat,
      savingAmt: b.saving,
      spendAmt: b.spend,
      bungaAmt: b.bunga,
      pinjamanAmt: b.pinjaman,
      lunasAmt: b.lunas,
    ));
  }
  return points;
}

List<StatsPoint> _buildMonthPoints(DateTime focus, List<FinanceTransaction> data, AppLang lang) {
  final monthShort = lang == AppLang.id
      ? const ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des']
      : const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final year = focus.year;
  final buckets = List.generate(12, (_) => _Bucket());
  for (final t in data) {
    if (t.date.year == year) buckets[t.date.month - 1].add(t);
  }
  final today = DateTime.now();
  double running = 0;
  final points = <StatsPoint>[];
  for (var i = 0; i < 12; i++) {
    final b = buckets[i];
    running += b.signedTotal;
    points.add(StatsPoint(
      label: monthShort[i],
      sub: (year % 100).toString().padLeft(2, '0'),
      value: running,
      rawValue: b.signedTotal,
      hasTx: b.hasTx,
      isToday: (i + 1) == today.month && year == today.year,
      domCat: b.domCat,
      savingAmt: b.saving,
      spendAmt: b.spend,
      bungaAmt: b.bunga,
      pinjamanAmt: b.pinjaman,
      lunasAmt: b.lunas,
    ));
  }
  return points;
}

List<StatsPoint> _buildYearPoints(DateTime focus, List<FinanceTransaction> data) {
  final currentYear = DateTime.now().year;
  final yearsSet = data.map((t) => t.date.year).toSet();
  if (yearsSet.isEmpty) {
    for (var y = currentYear - 2; y <= currentYear + 2; y++) {
      yearsSet.add(y);
    }
  }
  yearsSet.add(focus.year);
  final sorted = yearsSet.toList()..sort();
  final buckets = {for (final y in sorted) y: _Bucket()};
  for (final t in data) {
    buckets[t.date.year]?.add(t);
  }
  double running = 0;
  final points = <StatsPoint>[];
  for (final y in sorted) {
    final b = buckets[y]!;
    running += b.signedTotal;
    points.add(StatsPoint(
      label: '$y',
      sub: '',
      value: running,
      rawValue: b.signedTotal,
      hasTx: b.hasTx,
      isToday: y == focus.year,
      domCat: b.domCat,
      savingAmt: b.saving,
      spendAmt: b.spend,
      bungaAmt: b.bunga,
      pinjamanAmt: b.pinjaman,
      lunasAmt: b.lunas,
    ));
  }
  return points;
}

// ============================================================
// HALAMAN UTAMA
// ============================================================
class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final allItems = ref.watch(transactionsProvider);
    final cards = ref.watch(cardsProvider);
    final rawSelectedCard = ref.watch(selectedCardProvider);
    final isAllAccounts = rawSelectedCard == -1;
    final safeSelectedCard = cards.isEmpty
        ? 0
        : (rawSelectedCard >= cards.length ? cards.length - 1 : (rawSelectedCard < 0 ? 0 : rawSelectedCard));
    final items = isAllAccounts ? allItems : allItems.where((e) => e.cardIndex == safeSelectedCard).toList();

    final mode = ref.watch(statsModeProvider);
    final focus = ref.watch(statsFocusProvider);
    final points = _buildPoints(mode, focus, items, lang);

    final monthKey = _monthKey(focus);
    final budgets = ref.watch(statsBudgetsProvider);
    final budget = budgets[monthKey] ?? const StatsBudget();

    // Ringkasan kartu bawah SELALU mengikuti bulan yang sedang difokuskan
    // (bukan mode Hari/Bulan/Tahun yang sedang aktif di chart).
    double saving = 0, spend = 0, bunga = 0;
    for (final t in items) {
      if (t.date.year == focus.year && t.date.month == focus.month) {
        switch (_classify(t)) {
          case _TxCat.saving:
            saving += t.amount;
            break;
          case _TxCat.spend:
            spend += t.amount;
            break;
          case _TxCat.bunga:
            bunga += t.amount;
            break;
          default:
            break;
        }
      }
    }

    final topInset = MediaQuery.paddingOf(context).top;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = context.isDark;

    return SafeArea(
      top: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleStatsPointerDown,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              // Hero: full-bleed background (edge-to-edge, flush dengan bagian
              // paling atas layar) berisi header + chart tren. Gradasi memakai
              // context.cardColor asli (bukan warna hardcode nyaris hitam)
              // supaya mengikuti tema aplikasi yang sebenarnya: ungu muda di
              // mode terang (sama seperti kartu hero lama), ungu gelap di mode
              // gelap — tidak dipaksa dark terlepas dari mode aktif.
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(0, topInset + 16, 0, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(primary.withOpacity(isDark ? 0.22 : 0.14), context.cardColor),
                      Color.alphaBlend(primary.withOpacity(isDark ? 0.14 : 0.06), context.cardColor),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildHeader(context, lang, cards, isAllAccounts, safeSelectedCard),
                    ),
                    const SizedBox(height: 18),
                    _buildHeroCard(context, ref, lang, mode, focus, points),
                  ],
                ),
              ),
            ),
            // Sheet ringkasan overlap ke atas menutupi bagian bawah hero, dan
            // SELALU meregang mengisi sisa tinggi viewport lewat
            // SliverFillRemaining(hasScrollBody: false) — kalau konten sheet
            // lebih pendek dari layar, tingginya otomatis ditarik memenuhi
            // sisa ruang (tidak ada lagi celah warna scaffold di bawahnya);
            // kalau kontennya lebih panjang dari layar, sliver ini otomatis
            // kembali membiarkan seluruh CustomScrollView scroll normal.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(context.isDark ? 0.35 : 0.10), blurRadius: 24, offset: const Offset(0, -8))],
                ),
                child: Column(
                  children: [
                    _buildBreakdownSection(context, ref, lang, focus, monthKey, budget, saving, spend, bunga),
                    const SizedBox(height: 16),
                    _buildQuickActionButton(context, ref, lang),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== HEADER (gaya sendiri, konsisten dengan halaman lain di app) =====
Widget _buildHeader(BuildContext context, AppLang lang, List<FinanceCard> cards, bool isAllAccounts, int safeSelectedCard) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(Strings.t(lang, 'nav_statistic'),
              style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
          const CardSelectorButton(menuAlignment: GlassMenuAlignment.topRight),
        ],
      ),
      Text(
        Strings.t(lang, 'stats_subtitle_all'),
        style: TextStyle(color: context.textMuted),
      ),
    ],
  );
}

// ===== KARTU HERO (total + trend + chart + strip hari + toggle mode) =====
Widget _buildHeroCard(
  BuildContext context,
  WidgetRef ref,
  AppLang lang,
  StatsMode mode,
  DateTime focus,
  List<StatsPoint> points,
) {
  // Tidak lagi membungkus diri dalam Container/kartu sendiri — konten ini
  // sekarang duduk langsung di atas background ungu full-bleed yang
  // disiapkan oleh caller (StatisticsPage.build). Container hero itu
  // sekarang TIDAK punya padding horizontal lagi, jadi chart tren di
  // bawah ini otomatis melebar penuh sampai ke tepi layar tanpa perlu
  // widget breakout apa pun — bagian lain (total saldo & segmented
  // control) yang tetap perlu inset diberi Padding horizontal sendiri.
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _buildTotalAndTrend(context, lang, points),
      ),
      const SizedBox(height: 16),
      _TrendHeroChart(key: _statsChartKey, points: points, lang: lang),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _buildSegControl(context, ref, lang, mode),
      ),
    ],
  );
}

Widget _navChevron(BuildContext context, {required IconData icon, required VoidCallback? onTap}) {
  return IconButton(
    onPressed: onTap,
    splashRadius: 20,
    icon: Icon(icon, size: 22, color: onTap == null ? context.textFaint : context.iconMuted),
  );
}

Widget _buildSegControl(BuildContext context, WidgetRef ref, AppLang lang, StatsMode mode) {
  final primary = Theme.of(context).colorScheme.primary;
  final isDark = context.isDark;
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: (isDark ? Colors.black : Colors.black).withOpacity(isDark ? 0.25 : 0.045), borderRadius: BorderRadius.circular(999)),
    child: GlassSegmentedControl(
      segments: [
        GlassSegment(label: _l(lang, 'Hari', 'Day')),
        GlassSegment(label: _l(lang, 'Bulan', 'Month')),
        GlassSegment(label: _l(lang, 'Tahun', 'Year')),
      ],
      selectedIndex: mode.index,
      indicatorColor: primary.withOpacity(isDark ? 0.35 : 0.22),
      onSegmentSelected: (idx) => ref.read(statsModeProvider.notifier).state = StatsMode.values[idx],
      quality: GlassQuality.premium,
    ),
  );
}

String _focusLabel(AppLang lang, StatsMode mode, DateTime focus) {
  if (mode == StatsMode.day) return AppFormatters.monthYear(lang).format(focus);
  return '${focus.year}';
}

void _shiftFocus(WidgetRef ref, StatsMode mode, int delta) {
  final current = ref.read(statsFocusProvider);
  if (mode == StatsMode.day) {
    ref.read(statsFocusProvider.notifier).state = DateTime(current.year, current.month + delta, 1);
  } else {
    ref.read(statsFocusProvider.notifier).state = DateTime(current.year + delta, current.month, 1);
  }
}

void _showFocusPickerSheet(BuildContext context, WidgetRef ref, AppLang lang, StatsMode mode, DateTime focus) {
  int selMonth = focus.month;
  int selYear = focus.year;
  final years = <int>{for (var i = 0; i < 11; i++) DateTime.now().year - 7 + i, focus.year}.toList()..sort();
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l(lang, 'Pilih Periode', 'Choose Period'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
            const SizedBox(height: 18),
            Row(children: [
              if (mode == StatsMode.day)
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: selMonth,
                    decoration: InputDecoration(labelText: _l(lang, 'Bulan', 'Month')),
                    items: List.generate(12, (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(AppFormatters.monthYear(lang).format(DateTime(2024, i + 1, 1)).split(' ').first),
                        )),
                    onChanged: (v) => setModalState(() => selMonth = v!),
                  ),
                ),
              if (mode == StatsMode.day) const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: selYear,
                  decoration: InputDecoration(labelText: _l(lang, 'Tahun', 'Year')),
                  items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                  onChanged: (v) => setModalState(() => selYear = v!),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  ref.read(statsFocusProvider.notifier).state = DateTime(selYear, mode == StatsMode.day ? selMonth : 1, 1);
                  Navigator.pop(sheetContext);
                },
                child: Text(_l(lang, 'Terapkan', 'Apply')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildTotalAndTrend(BuildContext context, AppLang lang, List<StatsPoint> points) {
  final finalVal = points.isEmpty ? 0.0 : points.last.value;
  double firstNonZero = 0;
  for (final p in points) {
    if (p.value != 0) {
      firstNonZero = p.value;
      break;
    }
  }
  double pct = 0;
  if (firstNonZero != 0) {
    pct = ((finalVal - firstNonZero) / firstNonZero.abs()) * 100;
  } else if (finalVal != 0) {
    pct = 100;
  }
  final isPositiveTrend = pct >= 0;
  final trendColor = isPositiveTrend ? _colorPositive : _colorNegative;
  final isDark = context.isDark;
  return Column(children: [
    Text(_l(lang, 'Saldo Bersih Periode Ini', 'Net Balance This Period'),
        style: TextStyle(color: context.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    NumberFlow(
      value: finalVal,
      locale: 'id_ID',
      format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '),
      spring: NumberFlowSpring.ios,
      transformTiming: const TimingConfig(duration: Duration(milliseconds: 450), curve: Curves.easeInOut),
      opacityTiming: const TimingConfig(duration: Duration(milliseconds: 450), curve: Curves.easeOut),
      tabularNums: true,
      style: TextStyle(
        fontFamily: 'Satoshi',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: finalVal >= 0 ? context.textPrimary : _colorNegative,
      ),
    ),
    const SizedBox(height: 10),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: trendColor.withOpacity(isDark ? 0.20 : 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isPositiveTrend ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: trendColor),
        const SizedBox(width: 5),
        Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: trendColor)),
      ]),
    ),
  ]);
}

// ============================================================
// CHART TREN (custom painter, drag/tap untuk pilih titik + tooltip)
// ============================================================
class _TrendHeroChart extends StatefulWidget {
  final List<StatsPoint> points;
  final AppLang lang;
  const _TrendHeroChart({super.key, required this.points, required this.lang});

  @override
  State<_TrendHeroChart> createState() => _TrendHeroChartState();
}

class _TrendHeroChartState extends State<_TrendHeroChart> with SingleTickerProviderStateMixin {
  int? _selectedIndex;
  Timer? _hideTimer;
  late final AnimationController _growCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _growAnim = CurvedAnimation(parent: _growCtrl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _growCtrl.forward();
  }

  bool _sameSeries(List<StatsPoint> a, List<StatsPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].label != b[i].label) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant _TrendHeroChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSeries(oldWidget.points, widget.points)) {
      _hideTimer?.cancel();
      _selectedIndex = null;
      _growCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _growCtrl.dispose();
    super.dispose();
  }

  // Menyembunyikan tooltip otomatis & halus setelah beberapa saat tanpa
  // interaksi, supaya tooltip tidak terus menempel di layar.
  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  // Dipanggil dari luar (lihat Listener pembungkus halaman) saat pengguna
  // menekan area di luar grafik/strip hari atau menekan tombol lain di
  // tab ini — tooltip langsung disembunyikan dengan fade halus.
  void clearSelection() {
    _hideTimer?.cancel();
    if (_selectedIndex != null) setState(() => _selectedIndex = null);
  }

  void _selectFromDx(double dx, double width) {
    final points = widget.points;
    if (points.isEmpty) return;
    const padL = 26.0, padR = 26.0;
    final usable = (width - padL - padR).clamp(1.0, double.infinity);
    var rel = (dx - padL) / usable;
    rel = rel.clamp(0.0, 1.0);
    final idx = (rel * (points.length - 1)).round().clamp(0, points.length - 1);
    _scheduleAutoHide();
    if (idx != _selectedIndex) setState(() => _selectedIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final isDark = context.isDark;
    final allZero = points.isEmpty || points.every((p) => p.value == 0);
    if (allZero) {
      return SizedBox(
        height: 168,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.show_chart_rounded, size: 30, color: context.textFaint),
            const SizedBox(height: 8),
            Text(_l(widget.lang, 'Belum ada data di periode ini', 'No data in this period'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textFaint)),
          ]),
        ),
      );
    }

    final finalVal = points.last.value;
    final lineColor = finalVal >= 0 ? _colorPositive : _colorNegative;
    final effectiveIndex = _selectedIndex ??
        (() {
          final idx = points.indexWhere((p) => p.isToday);
          return idx != -1 ? idx : points.length - 1;
        })();

    // padL/padR di sini HANYA mengatur inset posisi TITIK DATA (garis &
    // dot pertama/terakhir digeser sedikit ke dalam agar tidak terpotong
    // tepat di tepi), BUKAN lebar area gambar chart itu sendiri — grid
    // horizontal & garis putus-putus nol (lihat _TrendChartPainter.paint)
    // sengaja digambar dari 0 sampai size.width penuh, independen dari
    // padL/padR, sehingga background/grid tetap full-bleed ke tepi kiri-
    // kanan layar sementara garis trennya sendiri punya sedikit "napas".
    const chartHeight = 150.0;
    const padL = 26.0, padR = 26.0, padT = 16.0, padB = 10.0;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final innerW = (width - padL - padR).clamp(1.0, double.infinity);
      final innerH = chartHeight - padT - padB;
      final values = points.map((p) => p.value).toList();
      double minV = values.reduce(min);
      double maxV = values.reduce(max);
      if (minV > 0) minV = 0;
      if (maxV < 0) maxV = 0;
      if (minV == maxV) maxV = minV + 1;
      final range = maxV - minV;
      final targetCoords = List.generate(points.length, (i) {
        final x = padL + (points.length == 1 ? innerW / 2 : innerW * i / (points.length - 1));
        final y = padT + innerH - ((points[i].value - minV) / range) * innerH;
        return Offset(x, y);
      });
      final zeroY = padT + innerH - ((0 - minV) / range) * innerH;

      final txDots = <MapEntry<int, Color>>[];
      for (var i = 0; i < points.length; i++) {
        if (points[i].hasTx) txDots.add(MapEntry(i, _colorForDomCat(points[i].domCat)));
      }

      final selectedAnchor = effectiveIndex >= 0 && effectiveIndex < targetCoords.length ? targetCoords[effectiveIndex] : null;
      final selectedColor = points[effectiveIndex].hasTx ? _colorForDomCat(points[effectiveIndex].domCat) : lineColor;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: chartHeight,
            width: double.infinity,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _selectFromDx(d.localPosition.dx, width),
              onPanUpdate: (d) => _selectFromDx(d.localPosition.dx, width),
              onTapDown: (d) => _selectFromDx(d.localPosition.dx, width),
              child: AnimatedBuilder(
                animation: _growAnim,
                builder: (context, _) {
                  final animatedCoords = List.generate(
                    targetCoords.length,
                    (i) => Offset(targetCoords[i].dx, _lerp(zeroY, targetCoords[i].dy, _growAnim.value)),
                  );
                  // Dot data pertama/terakhir sengaja punya inset (padL/padR)
                  // agar terlihat jelas & tidak terpotong di tepi. Tapi garis
                  // GRAFIK-nya sendiri diminta tetap full menyentuh tepi kiri-
                  // kanan layar — makanya di sini path GARIS/area (bukan posisi
                  // dot) diperpanjang secara flat (rata) dari dot pertama
                  // menuju x=0, dan dari dot terakhir menuju x=lebar penuh,
                  // pada ketinggian y yang sama seperti dot tersebut.
                  final lineCoords = <Offset>[
                    Offset(0, animatedCoords.first.dy),
                    ...animatedCoords,
                    Offset(width, animatedCoords.last.dy),
                  ];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(width, chartHeight),
                        painter: _TrendChartPainter(
                          lineCoords: lineCoords,
                          dotCoords: animatedCoords,
                          zeroY: zeroY,
                          lineColor: lineColor,
                          txDots: txDots,
                          selectedAnchor: selectedAnchor,
                          selectedColor: selectedColor,
                          gridColor: (isDark ? Colors.white : Colors.black).withOpacity(0.07),
                          dotCoreColor: context.cardColor,
                        ),
                      ),
                      if (selectedAnchor != null)
                        _buildTooltip(context, selectedAnchor, points[effectiveIndex], width, isDark, selectedColor, _selectedIndex != null),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildDayStrip(context, points, effectiveIndex),
        ],
      );
    });
  }

  Widget _buildTooltip(BuildContext context, Offset anchor, StatsPoint point, double chartWidth, bool isDark, Color accentColor, bool visible) {
    final bg = point.hasTx ? accentColor : (isDark ? const Color(0xFF2C2C2E) : context.cardColor);
    final textColor = point.hasTx ? Colors.white : context.textPrimary;
    final rows = <Widget>[];
    void addRow(String label, double amt, {bool negative = false}) {
      if (amt <= 0) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.9))),
          const SizedBox(width: 10),
          Text('${negative ? '-' : ''}${AppFormatters.rupiah(amt)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor)),
        ]),
      ));
    }

    addRow(_l(widget.lang, 'Saving', 'Saving'), point.savingAmt);
    addRow(_l(widget.lang, 'Hasil bunga', 'Interest'), point.bungaAmt);
    addRow(_l(widget.lang, 'Pengeluaran', 'Expense'), point.spendAmt, negative: true);
    addRow(_l(widget.lang, 'Pinjaman', 'Loan given'), point.pinjamanAmt, negative: true);
    addRow(_l(widget.lang, 'Pokok kembali', 'Principal repaid'), point.lunasAmt);

    const tooltipWidth = 152.0;
    var left = anchor.dx - tooltipWidth / 2;
    left = left.clamp(0.0, max(0.0, chartWidth - tooltipWidth));
    final estimatedHeight = 30.0 + rows.length * 16.0 + (rows.isNotEmpty ? 14 : 0);
    var top = anchor.dy - estimatedHeight - 14;
    if (top < 0) top = anchor.dy + 14;

    // Tooltip SELALU dipasang di tree (supaya transisi tampil/hilangnya
    // bisa animasi halus lewat AnimatedOpacity/AnimatedSlide alih-alih
    // muncul/hilang mendadak), tapi hanya benar-benar terlihat & bisa
    // diinteraksi saat `visible` true (ada seleksi aktif dari pengguna).
    return Positioned(
      left: left,
      top: top,
      width: tooltipWidth,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          opacity: visible ? 1.0 : 0.0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            offset: visible ? Offset.zero : const Offset(0, 0.06),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(AppFormatters.rupiah(point.value), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textColor)),
                if (rows.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: textColor.withOpacity(0.25))),
                  ...rows,
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayStrip(BuildContext context, List<StatsPoint> points, int activeIdx) {
    final visible = min(7, points.length);
    final start = max(0, min(points.length - visible, activeIdx - visible ~/ 2));
    final slice = points.sublist(start, start + visible);
    final isDark = context.isDark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(slice.length, (i) {
        final realIdx = start + i;
        final isActive = realIdx == activeIdx;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              _scheduleAutoHide();
              setState(() => _selectedIndex = realIdx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(slice[i].label,
                    style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, color: isActive ? context.textPrimary : context.textFaint)),
                if (slice[i].sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(slice[i].sub, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isActive ? context.textMuted : context.textFaint)),
                ],
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Path _smoothPath(List<Offset> coords) {
  final path = Path();
  if (coords.isEmpty) return path;
  path.moveTo(coords.first.dx, coords.first.dy);
  if (coords.length == 1) return path;
  for (var i = 0; i < coords.length - 1; i++) {
    final p0 = coords[i];
    final p1 = coords[i + 1];
    final cx1 = p0.dx + (p1.dx - p0.dx) * 0.5;
    final cy1 = p0.dy;
    final cx2 = p1.dx - (p1.dx - p0.dx) * 0.5;
    final cy2 = p1.dy;
    path.cubicTo(cx1, cy1, cx2, cy2, p1.dx, p1.dy);
  }
  return path;
}

void _drawDashedLine(Canvas canvas, Offset a, Offset b, Color color, {double dash = 4, double gap = 4, double strokeWidth = 1}) {
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = Offset((b.dx - a.dx) / total, (b.dy - a.dy) / total);
  final paint = Paint()
    ..color = color
    ..strokeWidth = strokeWidth;
  double covered = 0;
  while (covered < total) {
    final start = a + dir * covered;
    final endLen = min(covered + dash, total);
    final end = a + dir * endLen;
    canvas.drawLine(start, end, paint);
    covered += dash + gap;
  }
}

class _TrendChartPainter extends CustomPainter {
  // lineCoords: dipakai untuk menggambar GARIS & area gradasi — sudah
  // diperpanjang rata (flat) sampai x=0 dan x=lebar penuh (lihat
  // pemanggilnya di _TrendHeroChartState.build), sehingga garis selalu
  // menyentuh tepi kiri-kanan layar.
  // dotCoords: posisi ASLI titik data (dengan inset padL/padR) — dipakai
  // khusus untuk menggambar dot transaksi & anchor terpilih, supaya dot
  // pertama/terakhir tidak terpotong di tepi.
  final List<Offset> lineCoords;
  final List<Offset> dotCoords;
  final double zeroY;
  final Color lineColor;
  final List<MapEntry<int, Color>> txDots;
  final Offset? selectedAnchor;
  final Color selectedColor;
  final Color gridColor;
  final Color dotCoreColor;

  _TrendChartPainter({
    required this.lineCoords,
    required this.dotCoords,
    required this.zeroY,
    required this.lineColor,
    required this.txDots,
    required this.selectedAnchor,
    required this.selectedColor,
    required this.gridColor,
    required this.dotCoreColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dotCoords.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in [0.22, 0.5, 0.78]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    _drawDashedLine(canvas, Offset(0, zeroY), Offset(size.width, zeroY), gridColor.withOpacity(0.9));

    final linePath = _smoothPath(lineCoords);
    final areaPath = Path.from(linePath)
      ..lineTo(lineCoords.last.dx, zeroY)
      ..lineTo(lineCoords.first.dx, zeroY)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.28), lineColor.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final entry in txDots) {
      if (entry.key < 0 || entry.key >= dotCoords.length) continue;
      final c = dotCoords[entry.key];
      canvas.drawCircle(c, 4.2, Paint()..color = dotCoreColor);
      canvas.drawCircle(
        c,
        4.2,
        Paint()
          ..color = entry.value
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    if (selectedAnchor != null) {
      final c = selectedAnchor!;
      _drawDashedLine(canvas, Offset(c.dx, 0), Offset(c.dx, size.height), gridColor.withOpacity(0.9));
      canvas.drawCircle(c, 7, Paint()..color = selectedColor.withOpacity(0.20));
      canvas.drawCircle(c, 4.6, Paint()..color = dotCoreColor);
      canvas.drawCircle(
        c,
        4.6,
        Paint()
          ..color = selectedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) => true;
}

// ============================================================
// RINGKASAN / TARGET BULANAN
// ============================================================
Widget _buildBreakdownSection(
  BuildContext context,
  WidgetRef ref,
  AppLang lang,
  DateTime focus,
  String monthKey,
  StatsBudget budget,
  double saving,
  double spend,
  double bunga,
) {
  final isDark = context.isDark;
  final primary = Theme.of(context).colorScheme.primary;
  final int pctSaving = budget.targetSave > 0 ? ((saving / budget.targetSave) * 100).round() : 0;
  final int pctSpend = budget.limitSpend > 0 ? ((spend / budget.limitSpend) * 100).round() : 0;
  final int pctBunga = budget.targetSave > 0 ? ((bunga / budget.targetSave) * 100).round() : 0;
  final spendOver = pctSpend > 100;

  // Tidak lagi membungkus diri dalam kartu sendiri — sheet cardColor yang
  // sudah disiapkan oleh caller (StatisticsPage.build) menjadi permukaannya.
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
        child: Row(children: [
          Icon(Icons.pie_chart_rounded, size: 18, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_l(lang, 'Ringkasan', 'Summary')} ${AppFormatters.monthYear(lang).format(focus)}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _showBudgetSheet(context, ref, lang, monthKey, budget),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: primary.withOpacity(isDark ? 0.18 : 0.1), borderRadius: BorderRadius.circular(14)),
          child: Text(_l(lang, 'Atur Target', 'Set Target'), style: TextStyle(color: primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
    const SizedBox(height: 16),
    _breakdownCard(context,
        icon: Icons.savings_rounded,
        color: _colorPositive,
        label: _l(lang, 'Total Saving', 'Total Saving'),
        value: saving,
        pct: pctSaving,
        onTap: () => _showBudgetSheet(context, ref, lang, monthKey, budget)),
    const SizedBox(height: 12),
    _breakdownCard(context,
        icon: Icons.shopping_bag_rounded,
        color: spendOver ? const Color(0xFF8B0000) : _colorNegative,
        label: _l(lang, 'Pengeluaran', 'Expense'),
        value: spend,
        pct: pctSpend,
        onTap: () => _showBudgetSheet(context, ref, lang, monthKey, budget)),
    const SizedBox(height: 12),
    _breakdownCard(context,
        icon: Icons.trending_up_rounded,
        color: _colorInterest,
        label: _l(lang, 'Hasil Bunga', 'Interest Earned'),
        value: bunga,
        pct: pctBunga,
        onTap: () => _showBudgetSheet(context, ref, lang, monthKey, budget)),
  ]);
}

Widget _breakdownCard(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String label,
  required double value,
  required int pct,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (pct.clamp(0, 100)) / 100),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: color.withOpacity(0.12),
                color: color,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(AppFormatters.rupiah(value), style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w800, fontSize: 13, color: context.textPrimary)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
            child: Text('$pct%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      ]),
    ),
  );
}

void _showBudgetSheet(BuildContext context, WidgetRef ref, AppLang lang, String monthKey, StatsBudget current) {
  final targetCtrl = TextEditingController(text: current.targetSave > 0 ? AppFormatters.thousands.format(current.targetSave).replaceAll(',', '.') : '');
  final limitCtrl = TextEditingController(text: current.limitSpend > 0 ? AppFormatters.thousands.format(current.limitSpend).replaceAll(',', '.') : '');
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_l(lang, 'Atur Target Bulan Ini', 'Set Target for This Month'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
        const SizedBox(height: 18),
        TextField(
          controller: targetCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()],
          decoration: InputDecoration(labelText: _l(lang, 'Target Menabung', 'Savings Target'), prefixText: 'Rp '),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: limitCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()],
          decoration: InputDecoration(labelText: _l(lang, 'Batas Pengeluaran', 'Spending Limit'), prefixText: 'Rp '),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final t = double.tryParse(targetCtrl.text.replaceAll('.', '')) ?? 0;
              final l = double.tryParse(limitCtrl.text.replaceAll('.', '')) ?? 0;
              ref.read(statsBudgetsProvider.notifier).setBudget(monthKey, targetSave: t, limitSpend: l);
              Navigator.pop(sheetContext);
            },
            child: Text(_l(lang, 'Simpan', 'Save')),
          ),
        ),
      ]),
    ),
  );
}

Widget _buildQuickActionButton(BuildContext context, WidgetRef ref, AppLang lang) {
  final primary = Theme.of(context).colorScheme.primary;
  return PressScale(
    onTap: () => ref.read(tabProvider.notifier).state = 2,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [primary.withOpacity(0.85), primary.withOpacity(0.55)]),
        boxShadow: [BoxShadow(color: primary.withOpacity(0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 19),
        const SizedBox(width: 10),
        Text(_l(lang, 'Lihat Semua Transaksi', 'View All Transactions'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
    ),
  );
}