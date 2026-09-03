import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:solar_icons/solar_icons.dart';

import 'main.dart';

final geminiApiKeyProvider = StateProvider<String>((ref) {
  return ref.watch(prefsProvider).getString('gemini_api_key') ?? '';
});

final receiptOnlineFallbackEnabledProvider = StateProvider<bool>((ref) {
  return ref.watch(prefsProvider).getBool('receipt_online_fallback_enabled') ?? true;
});

enum ReceiptScanSource { offline, online }

class ReceiptScanResult {
  final String? merchant;
  final DateTime? date;
  final double? total;
  final String rawText;
  final ReceiptScanSource source;
  final bool confident;

  const ReceiptScanResult({
    this.merchant,
    this.date,
    this.total,
    required this.rawText,
    required this.source,
    required this.confident,
  });
}

class ReceiptParser {
  static final _totalKeywords = [
    'grand total', 'total belanja', 'total bayar', 'total tagihan',
    'total pembayaran', 'jumlah bayar', 'total', 'jumlah',
  ];

  static final _amountRegex = RegExp(
    r'(?:rp\.?\s*)?([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?|[0-9]{4,})',
    caseSensitive: false,
  );

  static double? _extractAmount(String line) {
    final matches = _amountRegex.allMatches(line);
    double? best;
    for (final m in matches) {
      final raw = m.group(1);
      if (raw == null) continue;
      final normalized = _normalizeNumber(raw);
      if (normalized == null) continue;
      if (best == null || normalized > best) best = normalized;
    }
    return best;
  }

  static double? _normalizeNumber(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (cleaned.isEmpty) return null;
    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    if (lastDot != -1 && lastComma != -1) {
      if (lastDot > lastComma) {
        cleaned = cleaned.replaceAll(',', '');
      } else {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      }
    } else {
      final sep = lastDot != -1 ? '.' : (lastComma != -1 ? ',' : null);
      if (sep != null) {
        final parts = cleaned.split(sep);
        final decimalLike = parts.length == 2 && parts.last.length == 2;
        if (!decimalLike) {
          cleaned = cleaned.replaceAll(sep, '');
        } else {
          cleaned = cleaned.replaceAll(sep, '.');
        }
      }
    }
    return double.tryParse(cleaned);
  }

  static double? parseTotal(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (final keyword in _totalKeywords) {
      for (final line in lines) {
        if (line.toLowerCase().contains(keyword)) {
          final amount = _extractAmount(line);
          if (amount != null && amount > 0) return amount;
        }
      }
    }
    double? largest;
    for (final line in lines) {
      final amount = _extractAmount(line);
      if (amount != null && (largest == null || amount > largest)) largest = amount;
    }
    return largest;
  }

  static final List<RegExp> _dateRegexes = [
    RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})'),
    RegExp(r'(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})'),
  ];

  static DateTime? parseDate(String text) {
    for (final regex in _dateRegexes) {
      final match = regex.firstMatch(text);
      if (match == null) continue;
      try {
        final g1 = int.parse(match.group(1)!);
        final g2 = int.parse(match.group(2)!);
        final g3 = int.parse(match.group(3)!);
        if (g1 > 31) {
          return DateTime(g1, g2, g3);
        }
        final year = g3 < 100 ? 2000 + g3 : g3;
        return DateTime(year, g2, g1);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? parseMerchant(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (final line in lines.take(5)) {
      final letters = line.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (letters.length >= 3) return line;
    }
    return lines.isNotEmpty ? lines.first : null;
  }
}

class ReceiptScannerService {
  Future<ReceiptScanResult> scanOffline(File imageFile) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognized = await recognizer.processImage(inputImage);
      final text = recognized.text;
      if (text.trim().isEmpty) {
        return const ReceiptScanResult(
          rawText: 'Tidak ada teks yang terdeteksi pada gambar. Coba foto ulang dengan pencahayaan lebih terang & fokus lebih tajam.',
          source: ReceiptScanSource.offline,
          confident: false,
        );
      }
      final total = ReceiptParser.parseTotal(text);
      final date = ReceiptParser.parseDate(text);
      final merchant = ReceiptParser.parseMerchant(text);
      return ReceiptScanResult(
        merchant: merchant,
        date: date,
        total: total,
        rawText: text,
        source: ReceiptScanSource.offline,
        confident: total != null && total > 0,
      );
    } catch (e) {
      return ReceiptScanResult(
        rawText: 'Gagal memindai teks (offline): $e',
        source: ReceiptScanSource.offline,
        confident: false,
      );
    } finally {
      recognizer.close();
    }
  }

  Future<ReceiptScanResult?> scanOnline(File imageFile, String apiKey) async {
    if (apiKey.trim().isEmpty) return null;
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey.trim()}',
      );
      const prompt = 'Kamu membaca foto struk belanja. Balas HANYA dengan JSON valid tanpa markdown, '
          'format persis: {"merchant": string atau null, "date": "YYYY-MM-DD" atau null, "total": number atau null}. '
          '"total" adalah jumlah akhir yang harus dibayar (grand total), dalam angka tanpa simbol mata uang.';
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}
                },
              ],
            }
          ],
          'generationConfig': {'temperature': 0.1},
        }),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final parts = candidates.first['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      var rawJsonText = (parts.first['text'] as String?)?.trim() ?? '';
      rawJsonText = rawJsonText
          .replaceAll(RegExp(r'^```json'), '')
          .replaceAll(RegExp(r'^```'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final parsed = jsonDecode(rawJsonText) as Map<String, dynamic>;
      final merchant = parsed['merchant'] as String?;
      final dateStr = parsed['date'] as String?;
      final totalRaw = parsed['total'];
      final total = totalRaw is num ? totalRaw.toDouble() : double.tryParse('$totalRaw');
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      return ReceiptScanResult(
        merchant: merchant,
        date: date,
        total: total,
        rawText: rawJsonText,
        source: ReceiptScanSource.online,
        confident: total != null && total > 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ReceiptScanResult> scan(File imageFile, {required bool onlineEnabled, required String apiKey}) async {
    final offlineResult = await scanOffline(imageFile);
    if (offlineResult.confident) return offlineResult;
    if (onlineEnabled && apiKey.trim().isNotEmpty) {
      final onlineResult = await scanOnline(imageFile, apiKey);
      if (onlineResult != null) return onlineResult;
    }
    return offlineResult;
  }
}

Future<void> _pickReceiptImage(BuildContext context, ImageSource source) async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(source: source, maxWidth: 2000, imageQuality: 92);
  if (picked == null || !context.mounted) return;
  Navigator.push(
    context,
    GlassPageRoute(builder: (_) => ReceiptScanPage(initialImageFile: File(picked.path))),
  );
}

Future<void> pickReceiptFromCameraAndPush(BuildContext context) async {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pindai Struk', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
            title: const Text('Ambil foto struk'),
            onTap: () {
              Navigator.pop(sheetContext);
              _pickReceiptImage(context, ImageSource.camera);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
            title: const Text('Pilih dari galeri'),
            onTap: () {
              Navigator.pop(sheetContext);
              _pickReceiptImage(context, ImageSource.gallery);
            },
          ),
        ]),
      ),
    ),
  );
}

class ReceiptScanPage extends ConsumerStatefulWidget {
  final File? initialImageFile;
  const ReceiptScanPage({super.key, this.initialImageFile});
  @override
  ConsumerState<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends ConsumerState<ReceiptScanPage> {
  final _service = ReceiptScannerService();
  File? _imageFile;
  ReceiptScanResult? _result;
  bool _scanning = false;
  String? _scanStage;

  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final initialFile = widget.initialImageFile;
    if (initialFile != null) {
      // Kamera sudah dibuka & foto sudah diambil SEBELUM halaman ini
      // di-push (lihat pickReceiptFromCameraAndPush di navbar), jadi di
      // sini tinggal langsung jalankan proses scan terhadap file yang
      // sudah ada, tanpa membuka kamera lagi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runScan(initialFile);
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _runScan(File file) async {
    setState(() {
      _imageFile = file;
      _result = null;
      _scanning = true;
      _scanStage = 'Membaca teks struk (offline)...';
    });
    final apiKey = ref.read(geminiApiKeyProvider);
    final onlineEnabled = ref.read(receiptOnlineFallbackEnabledProvider);
    final offlineResult = await _service.scanOffline(file);
    ReceiptScanResult finalResult = offlineResult;
    if (!offlineResult.confident && onlineEnabled && apiKey.trim().isNotEmpty) {
      if (mounted) setState(() => _scanStage = 'Nominal tidak terbaca jelas, mencoba AI online...');
      final onlineResult = await _service.scanOnline(file, apiKey);
      if (onlineResult != null) finalResult = onlineResult;
    }
    if (!mounted) return;
    setState(() {
      _result = finalResult;
      _scanning = false;
      _titleCtrl.text = finalResult.merchant ?? '';
      _amountCtrl.text = finalResult.total != null
          ? AppFormatters.thousands.format(finalResult.total).replaceAll(',', '.')
          : '';
      _selectedDate = finalResult.date ?? DateTime.now();
    });
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: source, maxWidth: 2000, imageQuality: 92);
    if (picked == null) return;
    await _runScan(File(picked.path));
  }

  void _showSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pindai Struk', style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Ambil foto struk'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndScan(ImageSource.camera);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Pilih dari galeri'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndScan(ImageSource.gallery);
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _save() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll('.', '')) ?? 0;
    if (amount <= 0 || _titleCtrl.text.trim().isEmpty) {
      showGlassSnackBar(context, 'Lengkapi judul & nominal terlebih dahulu', icon: Icons.warning_amber_rounded);
      return;
    }
    final cards = ref.read(cardsProvider);
    final rawSelectedCard = ref.read(selectedCardProvider);
    final cardIndex = (rawSelectedCard >= 0 && rawSelectedCard < cards.length) ? rawSelectedCard : 0;
    final sourceLabel = _result?.source == ReceiptScanSource.online ? 'AI online' : 'offline';
    ref.read(transactionsProvider.notifier).add(
          title: _titleCtrl.text.trim(),
          amount: amount,
          income: false,
          category: Strings.t(AppLang.en, 'cat_shopping'),
          note: 'Hasil pindai struk ($sourceLabel)',
          date: _selectedDate,
          cardIndex: cardIndex,
        );
    Navigator.pop(context);
    showGlassSnackBar(context, 'Transaksi dari struk tersimpan', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                Text('Pindai Struk', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_imageFile == null) _buildEmptyState(context),
                  if (_imageFile != null) _buildPreview(context),
                  if (_scanning) _buildScanningState(context),
                  if (_result != null && !_scanning) _buildResultForm(context),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 40),
      Icon(Icons.receipt_long_outlined, size: 72, color: context.iconMuted),
      const SizedBox(height: 20),
      Text('Foto atau pilih struk belanja untuk dipindai otomatis',
          textAlign: TextAlign.center, style: TextStyle(color: context.textMuted, fontSize: 14)),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _showSourceSheet,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Mulai Pindai'),
        ),
      ),
    ]);
  }

  Widget _buildPreview(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(_imageFile!, height: 220, width: double.infinity, fit: BoxFit.cover),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: _showSourceSheet, icon: const Icon(Icons.refresh, size: 16), label: const Text('Pindai ulang')),
      ),
    ]);
  }

  Widget _buildScanningState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
        const SizedBox(width: 14),
        Expanded(child: Text(_scanStage ?? 'Memindai...', style: TextStyle(color: context.textMuted, fontSize: 13))),
      ]),
    );
  }

  Widget _buildResultForm(BuildContext context) {
    final result = _result!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (result.source == ReceiptScanSource.online ? Theme.of(context).colorScheme.primary : Colors.grey).withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          result.source == ReceiptScanSource.online ? 'Dibaca via AI online' : 'Dibaca offline',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: result.source == ReceiptScanSource.online ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Nama toko / judul transaksi')),
      const SizedBox(height: 12),
      TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()],
        decoration: const InputDecoration(labelText: 'Total belanja', prefixText: 'Rp '),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) {
            setState(() => _selectedDate = DateTime(picked.year, picked.month, picked.day, _selectedDate.hour, _selectedDate.minute));
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Tanggal'),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: context.iconMuted),
            const SizedBox(width: 10),
            Text(AppFormatters.dateOnly.format(_selectedDate), style: TextStyle(fontSize: 14, color: context.textPrimary, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      if (result.rawText.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Lihat teks hasil pindai', style: TextStyle(fontSize: 12, color: context.textMuted)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(result.rawText, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: context.textMuted)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Simpan sebagai pengeluaran'))),
      const SizedBox(height: 30),
    ]);
  }
}

class ReceiptScanApiKeySettingsPage extends ConsumerStatefulWidget {
  const ReceiptScanApiKeySettingsPage({super.key});
  @override
  ConsumerState<ReceiptScanApiKeySettingsPage> createState() => _ReceiptScanApiKeySettingsPageState();
}

class _ReceiptScanApiKeySettingsPageState extends ConsumerState<ReceiptScanApiKeySettingsPage> {
  late final TextEditingController _keyCtrl;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: ref.read(geminiApiKeyProvider));
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = _keyCtrl.text.trim();
    ref.read(prefsProvider).setString('gemini_api_key', value);
    ref.read(geminiApiKeyProvider.notifier).state = value;
    showGlassSnackBar(context, 'API key disimpan', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final onlineEnabled = ref.watch(receiptOnlineFallbackEnabledProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                Expanded(
                  child: Text('Pengaturan AI Scan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Gunakan AI online sebagai fallback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                          const SizedBox(height: 4),
                          Text('Dipakai hanya kalau pemindaian offline gagal baca nominal', style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      GlassSwitch(
                        value: onlineEnabled,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (v) {
                          ref.read(receiptOnlineFallbackEnabledProvider.notifier).state = v;
                          ref.read(prefsProvider).setBool('receipt_online_fallback_enabled', v);
                        },
                        width: 56,
                        height: 28,
                        quality: GlassQuality.premium,
                        useOwnLayer: true,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Text('GEMINI API KEY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'API key',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Key disimpan lokal di perangkat ini saja (SharedPreferences), tidak ditulis di dalam kode aplikasi.',
                    style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Simpan API Key'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}