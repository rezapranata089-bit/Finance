import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:solar_icons/solar_icons.dart';

import 'main.dart';
import 'receipt_scanner.dart';
import 'statistics_page.dart';

const _backupChannel = MethodChannel('com.example.my_finance/gallery_picker');
const int _backupFormatVersion = 2;

String _bt(AppLang lang, String id, String en) => lang == AppLang.id ? id : en;

Map<String, dynamic> _asMap(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

double _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

class BackupSummary {
  final int cards;
  final int transactions;
  final int loans;
  final int budgets;
  const BackupSummary({required this.cards, required this.transactions, required this.loans, required this.budgets});
}

// ===================== BACKUP =====================

Map<String, dynamic> buildBackupJson(WidgetRef ref, {required bool includeApiKeys}) {
  final profile = ref.read(userProfileProvider);
  final txs = ref.read(transactionsProvider).where((t) => !t.id.startsWith('dummy-')).toList();
  final budgets = ref.read(statsBudgetsProvider);
  return {
    'app': 'my_finance',
    'version': _backupFormatVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'profile': {'name': profile.name},
    'cards': ref.read(cardsProvider).map((e) => e.toJson()).toList(),
    'transactions': txs.map((e) => e.toJson()).toList(),
    'loans': ref.read(loansProvider).map((e) => e.toJson()).toList(),
    'budgets': budgets.map((k, v) => MapEntry(k, v.toJson())),
    'customCategories': ref.read(customCategoriesProvider),
    'settings': {
      'categoryFeatureEnabled': ref.read(categoryFeatureEnabledProvider),
      'lang': ref.read(langProvider) == AppLang.id ? 'id' : 'en',
      'themeMode': ref.read(themeModeProvider).name,
      'themePalette': ref.read(themeProvider).name,
      'aiProvider': ref.read(aiProviderProvider) == AIProvider.groq ? 'groq' : 'gemini',
      'onlineEnabled': ref.read(receiptOnlineFallbackEnabledProvider),
      'geminiModel': ref.read(geminiModelProvider),
      'groqModel': ref.read(groqModelProvider),
      if (includeApiKeys) 'geminiKeys': ref.read(geminiApiKeysProvider),
      if (includeApiKeys) 'groqKeys': ref.read(groqApiKeysProvider),
    },
  };
}

// ===================== RESTORE =====================

void _applySettings(WidgetRef ref, Map<String, dynamic> s) {
  final prefs = ref.read(prefsProvider);

  final cat = s['categoryFeatureEnabled'];
  if (cat is bool) {
    ref.read(categoryFeatureEnabledProvider.notifier).state = cat;
    prefs.setBool('category_feature_enabled', cat);
  }

  final lang = s['lang'];
  if (lang == 'id' || lang == 'en') {
    ref.read(langProvider.notifier).state = lang == 'id' ? AppLang.id : AppLang.en;
    prefs.setString('app_lang', '$lang');
  }

  final modeName = s['themeMode'];
  if (modeName is String) {
    final match = ThemeMode.values.where((m) => m.name == modeName);
    if (match.isNotEmpty) {
      ref.read(themeModeProvider.notifier).state = match.first;
      prefs.setString('app_theme_mode', modeName);
    }
  }

  final paletteName = s['themePalette'];
  if (paletteName is String) {
    final match = appPalettes.where((p) => p.name == paletteName);
    if (match.isNotEmpty) {
      ref.read(themeProvider.notifier).state = match.first;
      prefs.setString('app_theme_palette', paletteName);
    }
  }

  final provider = s['aiProvider'];
  if (provider == 'groq' || provider == 'gemini') {
    ref.read(aiProviderProvider.notifier).state = provider == 'groq' ? AIProvider.groq : AIProvider.gemini;
    prefs.setString('ai_provider', '$provider');
  }

  final online = s['onlineEnabled'];
  if (online is bool) {
    ref.read(receiptOnlineFallbackEnabledProvider.notifier).state = online;
    prefs.setBool('receipt_online_fallback_enabled', online);
  }

  final gModel = s['geminiModel'];
  if (gModel is String && gModel.trim().isNotEmpty) {
    ref.read(geminiModelProvider.notifier).state = gModel.trim();
    prefs.setString('gemini_model', gModel.trim());
  }
  final qModel = s['groqModel'];
  if (qModel is String && qModel.trim().isNotEmpty) {
    ref.read(groqModelProvider.notifier).state = qModel.trim();
    prefs.setString('groq_model', qModel.trim());
  }

  final gKeys = s['geminiKeys'];
  if (gKeys is List) {
    ref.read(geminiApiKeysProvider.notifier).setAll(gKeys.map((e) => '$e').toList());
  }
  final qKeys = s['groqKeys'];
  if (qKeys is List) {
    ref.read(groqApiKeysProvider.notifier).setAll(qKeys.map((e) => '$e').toList());
  }
}

void _applyData(
  WidgetRef ref, {
  required List<FinanceCard> cards,
  required List<FinanceTransaction> txs,
  required List<Loan> loans,
  required Map<String, StatsBudget> budgets,
  List<String>? categories,
}) {
  ref.read(cardsProvider.notifier).replaceAll(cards);
  ref.read(transactionsProvider.notifier).replaceAll(txs);
  ref.read(loansProvider.notifier).replaceAll(loans);
  ref.read(statsBudgetsProvider.notifier).replaceAll(budgets);
  if (categories != null) {
    ref.read(customCategoriesProvider.notifier).replaceAll(categories);
  }
  ref.read(dummyTransactionsHolderProvider.notifier).state = [];
  ref.read(dummyDataActiveProvider.notifier).state = false;
  ref.read(prefsProvider).setBool('dummy_data_active', false);
  ref.read(selectedCardProvider.notifier).state = -1;
}

BackupSummary restoreFromNativeBackup(WidgetRef ref, Map<String, dynamic> json) {
  var cards = (json['cards'] as List? ?? const []).map((e) => FinanceCard.fromJson(_asMap(e))).toList();
  if (cards.isEmpty) {
    cards = [const FinanceCard(number: '**** 0001', name: 'Dompet Utama')];
  }
  final txs = (json['transactions'] as List? ?? const []).map((e) => FinanceTransaction.fromJson(_asMap(e))).toList();
  final loans = (json['loans'] as List? ?? const []).map((e) => Loan.fromJson(_asMap(e))).toList();
  final budgets = _asMap(json['budgets']).map((k, v) => MapEntry(k, StatsBudget.fromJson(_asMap(v))));
  final categories = (json['customCategories'] as List? ?? const []).map((e) => '$e').toList();

  _applyData(ref, cards: cards, txs: txs, loans: loans, budgets: budgets, categories: categories);
  _applySettings(ref, _asMap(json['settings']));

  final profileName = '${_asMap(json['profile'])['name'] ?? ''}'.trim();
  if (profileName.isNotEmpty) {
    ref.read(userProfileProvider.notifier).updateName(profileName);
  }
  return BackupSummary(cards: cards.length, transactions: txs.length, loans: loans.length, budgets: budgets.length);
}

DateTime _legacyDate(Map<String, dynamic> d) {
  final parsed = DateTime.tryParse('${d['tanggal'] ?? ''}');
  if (parsed != null) return parsed.toLocal();
  final ts = _asDouble(d['timestamp']).toInt();
  if (ts > 0) return DateTime.fromMillisecondsSinceEpoch(ts);
  return DateTime.now();
}

// Mengonversi file backup LAMA (ekspor Firebase: budgets / members /
// transactions / settings) ke struktur data aplikasi ini.
// [m] = pengali nominal (backup lama menyimpan angka dalam ribuan rupiah).
BackupSummary restoreFromLegacyBackup(WidgetRef ref, Map<String, dynamic> json, double m) {
  final membersRaw = _asMap(json['members']);
  final txRaw = _asMap(json['transactions']);
  final budgetsRaw = _asMap(json['budgets']);
  final settingsRaw = _asMap(json['settings']);
  final modalAwal = _asDouble(settingsRaw['modalAwal']);

  final hasMembers = membersRaw.isNotEmpty;
  final cards = <FinanceCard>[
    FinanceCard(number: '**** 0001', name: 'Dompet Utama', initialBalance: modalAwal * m),
    if (hasMembers) const FinanceCard(number: '**** PTG', name: 'Kartu Piutang', initialBalance: 0, type: CardType.piutang),
  ];
  final piutangIdx = hasMembers ? 1 : 0;

  final memberIdByName = <String, String>{};
  final memberNameById = <String, String>{};
  for (final e in membersRaw.entries) {
    final name = '${_asMap(e.value)['nama'] ?? ''}'.trim();
    memberNameById[e.key] = name;
    if (name.isNotEmpty) memberIdByName[name.toLowerCase()] = e.key;
  }

  final entries = txRaw.entries.map((e) => MapEntry(e.key, _asMap(e.value))).toList()
    ..sort((a, b) => _asDouble(a.value['timestamp']).compareTo(_asDouble(b.value['timestamp'])));

  final txList = <FinanceTransaction>[];
  final paymentsByLoan = <String, List<LoanPayment>>{};
  final firstInterest = <String, DateTime>{};

  for (final e in entries) {
    final d = e.value;
    final kategori = '${d['kategori'] ?? ''}'.trim().toLowerCase();
    final nama = '${d['nama'] ?? ''}'.trim();
    final ket = '${d['keterangan'] ?? ''}'.trim();
    final amount = _asDouble(d['nominal']) * m;
    if (amount <= 0) continue;
    final date = _legacyDate(d);
    final id = e.key;

    if (kategori.contains('bunga')) {
      final loanId = memberIdByName[nama.toLowerCase()];
      if (loanId != null) {
        final borrower = memberNameById[loanId] ?? nama;
        txList.add(FinanceTransaction(
          id: id,
          title: 'Bunga · $borrower',
          category: 'Bunga Pinjaman',
          note: ket,
          amount: amount,
          income: true,
          date: date,
          cardIndex: piutangIdx,
          loanId: loanId,
        ));
        paymentsByLoan.putIfAbsent(loanId, () => []).add(
              LoanPayment(transactionId: id, date: date, interestAmount: amount, principalAmount: 0, note: ket),
            );
        final prev = firstInterest[loanId];
        if (prev == null || date.isBefore(prev)) firstInterest[loanId] = date;
        continue;
      }
      txList.add(FinanceTransaction(
        id: id,
        title: ket.isEmpty ? 'Hasil bunga' : ket,
        category: 'Income',
        note: '',
        amount: amount,
        income: true,
        date: date,
        cardIndex: 0,
      ));
    } else if (kategori == 'saving') {
      txList.add(FinanceTransaction(
        id: id,
        title: ket.isEmpty ? 'Saving' : ket,
        category: 'Income',
        note: '',
        amount: amount,
        income: true,
        date: date,
        cardIndex: 0,
      ));
    } else {
      txList.add(FinanceTransaction(
        id: id,
        title: ket.isEmpty ? 'Pengeluaran' : ket,
        category: 'Other',
        note: '',
        amount: amount,
        income: false,
        date: date,
        cardIndex: 0,
      ));
    }
  }
  txList.sort((a, b) => b.date.compareTo(a.date));

  final memberEntries = membersRaw.entries.map((e) => MapEntry(e.key, _asMap(e.value))).toList()
    ..sort((a, b) => _asDouble(b.value['timestamp']).compareTo(_asDouble(a.value['timestamp'])));
  final loans = <Loan>[];
  for (final me in memberEntries) {
    final md = me.value;
    final name = memberNameById[me.key] ?? '';
    if (name.isEmpty) continue;
    final pokok = _asDouble(md['pokok']) * m;
    final bunga = _asDouble(md['bunga']) * m;
    final lunas = md['isLunas'] == true;
    final percent = pokok > 0 ? double.parse((bunga / pokok * 100).toStringAsFixed(2)) : 0.0;
    final createdMs = _asDouble(md['timestamp']).toInt();
    DateTime start = createdMs > 0 ? DateTime.fromMillisecondsSinceEpoch(createdMs) : DateTime.now();
    final first = firstInterest[me.key];
    if (first != null && first.isBefore(start)) start = first;
    loans.add(Loan(
      id: me.key,
      borrowerName: name,
      principal: pokok,
      remainingPrincipal: lunas ? 0 : pokok,
      interestPercent: percent,
      interestType: LoanInterestType.flat,
      startDate: start,
      status: lunas ? LoanStatus.paid : LoanStatus.active,
      cardIndex: piutangIdx,
      sourceCardIndex: 0,
      payments: paymentsByLoan[me.key] ?? const [],
    ));
  }

  final budgets = <String, StatsBudget>{};
  for (final e in budgetsRaw.entries) {
    final b = _asMap(e.value);
    budgets[e.key] = StatsBudget(
      targetSave: _asDouble(b['targetSave']) * m,
      limitSpend: _asDouble(b['limitSpend']) * m,
    );
  }

  _applyData(ref, cards: cards, txs: txList, loans: loans, budgets: budgets);

  final ai = _asMap(settingsRaw['aiConfig']);
  List<String> keysOf(String provider) {
    final list = _asMap(ai[provider])['keys'];
    if (list is! List) return const <String>[];
    return list
        .map((e) => e is Map ? '${e['key'] ?? ''}'.trim() : '$e'.trim())
        .where((k) => k.isNotEmpty)
        .toList();
  }

  final geminiKeys = keysOf('gemini');
  final groqKeys = keysOf('groq');
  if (geminiKeys.isNotEmpty) ref.read(geminiApiKeysProvider.notifier).setAll(geminiKeys);
  if (groqKeys.isNotEmpty) ref.read(groqApiKeysProvider.notifier).setAll(groqKeys);
  final prov = ai['provider'];
  if (prov == 'groq' || prov == 'gemini') {
    ref.read(aiProviderProvider.notifier).state = prov == 'groq' ? AIProvider.groq : AIProvider.gemini;
    ref.read(prefsProvider).setString('ai_provider', '$prov');
  }

  return BackupSummary(cards: cards.length, transactions: txList.length, loans: loans.length, budgets: budgets.length);
}

// ===================== HALAMAN =====================

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});
  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  final ScrollController _scrollController = ScrollController();
  bool _includeKeys = true;
  bool _busy = false;

  bool get _nativeFiles => !kIsWeb && Platform.isAndroid;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _backup() async {
    final lang = ref.read(langProvider);
    setState(() => _busy = true);
    try {
      final json = buildBackupJson(ref, includeApiKeys: _includeKeys);
      final text = const JsonEncoder.withIndent('  ').convert(json);
      final fileName = 'my_finance_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      if (_nativeFiles) {
        final saved = await _backupChannel.invokeMethod<String>('exportBackup', {'fileName': fileName, 'content': text});
        if (saved == null) return;
        if (!mounted) return;
        showGlassSnackBar(context, _bt(lang, 'Backup berhasil disimpan', 'Backup saved successfully'), icon: Icons.check_circle_outline);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        showGlassSnackBar(context, _bt(lang, 'Backup disalin ke clipboard', 'Backup copied to clipboard'), icon: Icons.copy_rounded);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, _bt(lang, 'Gagal menyimpan backup: ${e.message}', 'Failed to save backup: ${e.message}'), icon: Icons.error_outline);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, _bt(lang, 'Gagal membuat backup: $e', 'Failed to create backup: $e'), icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final lang = ref.read(langProvider);
    setState(() => _busy = true);
    try {
      String? text;
      if (_nativeFiles) {
        text = await _backupChannel.invokeMethod<String>('importBackup');
      } else {
        final data = await Clipboard.getData('text/plain');
        text = data?.text;
      }
      if (text == null || text.trim().isEmpty) {
        if (!_nativeFiles && mounted) {
          showGlassSnackBar(context, _bt(lang, 'Clipboard kosong', 'Clipboard is empty'), icon: Icons.info_outline);
        }
        return;
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('root');
      final json = Map<String, dynamic>.from(decoded);
      final isNative = json['app'] == 'my_finance';
      final isLegacy = !isNative && json['transactions'] is Map;
      if (!isNative && !isLegacy) throw const FormatException('format');
      if (!mounted) return;

      double multiplier = 1.0;
      if (isLegacy) {
        final picked = await _askLegacyMultiplier(lang);
        if (picked == null) return;
        multiplier = picked;
      } else {
        final ok = await _confirmReplace(lang);
        if (ok != true) return;
      }

      final summary = isLegacy ? restoreFromLegacyBackup(ref, json, multiplier) : restoreFromNativeBackup(ref, json);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showGlassSnackBar(
        context,
        _bt(
          lang,
          'Restore berhasil: ${summary.transactions} transaksi, ${summary.cards} kartu, ${summary.loans} piutang',
          'Restore complete: ${summary.transactions} transactions, ${summary.cards} cards, ${summary.loans} loans',
        ),
        icon: Icons.check_circle_outline,
      );
    } on FormatException {
      if (!mounted) return;
      showGlassSnackBar(context, _bt(lang, 'File backup tidak valid', 'Invalid backup file'), icon: Icons.error_outline);
    } on PlatformException catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, _bt(lang, 'Gagal membaca file: ${e.message}', 'Failed to read file: ${e.message}'), icon: Icons.error_outline);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, _bt(lang, 'Gagal restore: $e', 'Restore failed: $e'), icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<double?> _askLegacyMultiplier(AppLang lang) {
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_bt(lang, 'Impor Backup Lama', 'Import Legacy Backup')),
        content: Text(_bt(
          lang,
          'File ini berformat backup lama. Semua data aplikasi saat ini akan DIGANTI.\n\nBackup lama menyimpan nominal dalam ribuan (mis. 150 = Rp 150.000). Kalikan nominal dengan 1.000?',
          'This file uses the legacy backup format. All current app data will be REPLACED.\n\nThe legacy backup stores amounts in thousands (e.g. 150 = Rp 150,000). Multiply amounts by 1,000?',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_bt(lang, 'Batal', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 1.0), child: Text(_bt(lang, 'Apa adanya', 'As is'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 1000.0), child: Text(_bt(lang, 'Ya, ×1.000', 'Yes, ×1,000'))),
        ],
      ),
    );
  }

  Future<bool?> _confirmReplace(AppLang lang) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_bt(lang, 'Restore Data', 'Restore Data')),
        content: Text(_bt(
          lang,
          'Semua data aplikasi saat ini (transaksi, kartu, piutang, target) akan DIGANTI dengan isi file backup.',
          'All current app data (transactions, cards, loans, targets) will be REPLACED with the backup file contents.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_bt(lang, 'Batal', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_bt(lang, 'Ganti Data', 'Replace Data'))),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: context.textMuted, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    final txCount = ref.watch(transactionsProvider).length;
    final cardCount = ref.watch(cardsProvider).length;
    final loanCount = ref.watch(loansProvider).length;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 78, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: primary.withOpacity(isDark ? 0.18 : 0.1), shape: BoxShape.circle),
                        child: Icon(SolarIconsOutline.cloudUpload, color: primary, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(_bt(lang, 'Data tersimpan saat ini', 'Currently stored data'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      _stat(context, _bt(lang, 'Transaksi', 'Transactions'), '$txCount'),
                      const SizedBox(width: 10),
                      _stat(context, _bt(lang, 'Kartu', 'Cards'), '$cardCount'),
                      const SizedBox(width: 10),
                      _stat(context, _bt(lang, 'Piutang', 'Loans'), '$loanCount'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_bt(lang, 'Sertakan API key AI', 'Include AI API keys'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          _bt(lang, 'File backup akan berisi API key dalam bentuk teks biasa. Simpan file dengan aman.', 'The backup file will contain API keys as plain text. Keep the file safe.'),
                          style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    GlassSwitch(
                      value: _includeKeys,
                      activeColor: primary,
                      onChanged: (v) => setState(() => _includeKeys = v),
                      width: 56,
                      height: 28,
                      quality: GlassQuality.premium,
                      useOwnLayer: true,
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _backup,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file_rounded, size: 20),
                    label: Text(_nativeFiles ? _bt(lang, 'Backup ke File', 'Backup to File') : _bt(lang, 'Salin Backup ke Clipboard', 'Copy Backup to Clipboard')),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(_nativeFiles ? _bt(lang, 'Restore dari File', 'Restore from File') : _bt(lang, 'Restore dari Clipboard', 'Restore from Clipboard')),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _bt(
                      lang,
                      'Restore mendukung file backup aplikasi ini maupun file backup lama (ekspor Firebase). Foto/video profil tidak ikut dibackup.',
                      'Restore supports this app\'s backup files as well as legacy backup files (Firebase export). Profile photo/video are not included in backups.',
                    ),
                    style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(children: [
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
                  ScrollFadeTitle(
                    controller: _scrollController,
                    child: Text(Strings.t(lang, 'backup_data'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}