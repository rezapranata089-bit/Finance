import 'dart:async';
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

enum AIProvider { gemini, groq }

final aiProviderProvider = StateProvider<AIProvider>((ref) {
  final saved = ref.watch(prefsProvider).getString('ai_provider');
  return saved == 'groq' ? AIProvider.groq : AIProvider.gemini;
});

class ApiKeyListNotifier extends StateNotifier<List<String>> {
  final SharedPreferences prefs;
  final String storageKey;
  final String legacyKey;

  ApiKeyListNotifier(this.prefs, this.storageKey, this.legacyKey) : super(_load(prefs, storageKey, legacyKey));

  static List<String> _load(SharedPreferences prefs, String storageKey, String legacyKey) {
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    // Migrasi dari format lama (satu API key tunggal) supaya pengguna yang
    // sudah pernah mengisi key sebelumnya tidak kehilangan pengaturannya.
    final legacy = prefs.getString(legacyKey);
    if (legacy != null && legacy.trim().isNotEmpty) {
      return [legacy.trim()];
    }
    return [];
  }

  void setAll(List<String> keys) {
    state = keys.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    prefs.setString(storageKey, jsonEncode(state));
  }
}

final geminiApiKeysProvider = StateNotifierProvider<ApiKeyListNotifier, List<String>>((ref) {
  return ApiKeyListNotifier(ref.watch(prefsProvider), 'gemini_api_keys', 'gemini_api_key');
});

final geminiModelProvider = StateProvider<String>((ref) {
  return ref.watch(prefsProvider).getString('gemini_model') ?? 'gemini-flash-latest';
});

final groqApiKeysProvider = StateNotifierProvider<ApiKeyListNotifier, List<String>>((ref) {
  return ApiKeyListNotifier(ref.watch(prefsProvider), 'groq_api_keys', 'groq_api_key');
});

final groqModelProvider = StateProvider<String>((ref) {
  return ref.watch(prefsProvider).getString('groq_model') ?? 'meta-llama/llama-4-scout-17b-16e-instruct';
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

  // Baris yang mengandung salah satu kata ini TIDAK PERNAH dianggap sebagai
  // baris "Total", baik lewat keyword match maupun fallback nominal
  // terbesar. Tanpa ini, baris "Tunai" (uang yang dibayarkan pelanggan,
  // biasanya >= total) atau "Kembali" (kembalian) bisa salah terambil
  // sebagai total kalau urutan baris hasil OCR tidak persis mengikuti
  // urutan visual struk (umum terjadi pada foto struk yang miring/tidak
  // rata).
  static const _excludedFromTotalWords = ['tunai', 'kembali', 'cash', 'change'];

  static bool _isExcludedTotalLine(String line) {
    final lower = line.toLowerCase();
    return _excludedFromTotalWords.any((w) => lower.contains(w));
  }

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

    // Struk Indonesia praktis tidak pernah punya desimal (Rupiah tidak
    // punya pecahan), tapi banyak software kasir mencetak 3 digit "000" di
    // belakang seakan-akan desimal (mis. "58.200,000"), dan OCR sering
    // salah membaca koma sebagai titik sehingga jadi "58.200.000" yang
    // tanpa penanganan khusus akan salah dikalikan 1000x (jadi 58 juta,
    // bukan 58 ribu). Kalau grup TERAKHIR setelah separator persis "000"
    // DAN masih ada separator lain sebelumnya (bukan angka kecil tunggal
    // seperti "1.000"), buang grup akhir itu — sisanya murni pemisah
    // ribuan, apa pun karakter separatornya (titik atau koma).
    final trailingZeroMatch = RegExp(r'^(.*)[.,]000$').firstMatch(cleaned);
    if (trailingZeroMatch != null) {
      final head = trailingZeroMatch.group(1)!;
      if (RegExp(r'[.,]').hasMatch(head)) {
        return double.tryParse(head.replaceAll(RegExp(r'[.,]'), ''));
      }
    }

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
        if (_isExcludedTotalLine(line)) continue;
        if (line.toLowerCase().contains(keyword)) {
          final amount = _extractAmount(line);
          if (amount != null && amount > 0) return amount;
        }
      }
    }
    double? largest;
    for (final line in lines) {
      if (_isExcludedTotalLine(line)) continue;
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
      // PlatformException di titik ini umumnya BUKAN bug di kode Dart,
      // melainkan recognizer ML Kit gagal diinisialisasi secara native di
      // perangkat ini (sering terjadi di ROM Android custom/OEM dengan
      // komponen Google Play Services yang dimodifikasi/terbatas). Stack
      // trace Java mentah tidak berguna bagi pengguna awam, jadi tampilkan
      // pesan yang lebih jelas & actionable (arahkan ke fallback AI online).
      final isPlatformFailure = e is PlatformException;
      final friendlyMessage = isPlatformFailure
          ? 'Pemindaian offline tidak didukung di perangkat ini. Aktifkan "AI online" di Pengaturan > Pengaturan AI Scan agar tetap bisa memindai struk.'
          : 'Gagal memindai teks (offline): $e';
      return ReceiptScanResult(
        rawText: friendlyMessage,
        source: ReceiptScanSource.offline,
        confident: false,
      );
    } finally {
      recognizer.close();
    }
  }

  static const String _receiptPrompt =
      'Kamu membaca foto struk belanja. Balas HANYA dengan JSON valid tanpa markdown, '
      'format persis: {"merchant": string atau null, "date": "YYYY-MM-DD" atau null, "total": number atau null}. '
      '"total" adalah jumlah akhir yang harus dibayar (grand total), dalam angka tanpa simbol mata uang.';

  ReceiptScanResult _parseJsonScanResult(String rawJsonText) {
    var cleaned = rawJsonText.trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^```json'), '')
        .replaceAll(RegExp(r'^```'), '')
        .replaceAll(RegExp(r'```$'), '')
        .trim();
    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    final merchant = parsed['merchant'] as String?;
    final dateStr = parsed['date'] as String?;
    final totalRaw = parsed['total'];
    final total = totalRaw is num ? totalRaw.toDouble() : double.tryParse('$totalRaw');
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    return ReceiptScanResult(
      merchant: merchant,
      date: date,
      total: total,
      rawText: cleaned,
      source: ReceiptScanSource.online,
      confident: total != null && total > 0,
    );
  }

  // AI online sekarang bisa dipilih manual antara Gemini atau Groq, dan
  // nama model diisi manual oleh pengguna di Pengaturan AI Scan (bukan
  // hardcode satu model tetap), supaya kalau suatu model dimatikan/
  // deprecated oleh provider-nya, pengguna tinggal ganti nama model tanpa
  // perlu update aplikasi.
  Future<ReceiptScanResult?> scanOnline(File imageFile, {required AIProvider provider, required List<String> apiKeys, required String model}) async {
    final trimmedModel = model.trim();
    final keys = apiKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty || trimmedModel.isEmpty) return null;
    ReceiptScanResult? lastResult;
    for (final key in keys) {
      try {
        final result = provider == AIProvider.groq
            ? await _scanOnlineGroq(imageFile, key, trimmedModel)
            : await _scanOnlineGemini(imageFile, key, trimmedModel);
        if (result != null && result.confident) return result;
        lastResult ??= result;
      } catch (_) {
        // Key ini gagal dipanggil (mis. kena limit kuota atau tidak
        // valid) — lanjut coba API key berikutnya dalam daftar.
      }
    }
    return lastResult;
  }

  Future<ReceiptScanResult?> _scanOnlineGemini(File imageFile, String apiKey, String model) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _receiptPrompt},
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
    final rawJsonText = (parts.first['text'] as String?)?.trim() ?? '';
    if (rawJsonText.isEmpty) return null;
    return _parseJsonScanResult(rawJsonText);
  }

  // Groq memakai endpoint chat completion bergaya OpenAI dengan gambar
  // dikirim sebagai data URI base64 di dalam "image_url", berbeda dari
  // format "inline_data" ala Gemini. Nama model harus salah satu model
  // Groq yang mendukung vision, diisi manual oleh pengguna sendiri.
  Future<ReceiptScanResult?> _scanOnlineGroq(File imageFile, String apiKey, String model) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _receiptPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          }
        ],
      }),
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final rawJsonText = (choices.first['message']?['content'] as String?)?.trim() ?? '';
    if (rawJsonText.isEmpty) return null;
    return _parseJsonScanResult(rawJsonText);
  }

  /// Melakukan panggilan ringan (teks saja, tanpa gambar) ke Gemini API
  /// untuk memverifikasi API key & konektivitas, dan mengembalikan pesan
  /// yang jelas (bukan diam-diam gagal) supaya pengguna tahu persis kenapa
  /// kalau gagal — mis. key salah, kuota habis, atau tidak ada internet.
  Future<({bool success, String message})> testApiKey(String apiKey, {required AIProvider provider, required String model}) async {
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim();
    if (trimmedKey.isEmpty) {
      return (success: false, message: 'API key masih kosong.');
    }
    if (trimmedModel.isEmpty) {
      return (success: false, message: 'Nama model masih kosong.');
    }
    try {
      final http.Response response;
      if (provider == AIProvider.groq) {
        response = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $trimmedKey',
          },
          body: jsonEncode({
            'model': trimmedModel,
            'messages': [
              {'role': 'user', 'content': 'Balas hanya dengan kata OK.'}
            ],
          }),
        ).timeout(const Duration(seconds: 15));
      } else {
        response = await http.post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$trimmedModel:generateContent?key=$trimmedKey',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Balas hanya dengan kata OK.'}
                ],
              }
            ],
          }),
        ).timeout(const Duration(seconds: 15));
      }
      if (response.statusCode == 200) {
        final providerName = provider == AIProvider.groq ? 'Groq' : 'Gemini';
        return (success: true, message: 'Berhasil! API key & model valid, bisa terhubung ke $providerName.');
      }
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        detail = (decoded['error']?['message'] as String?) ?? response.body;
      } catch (_) {}
      return (success: false, message: 'Gagal (kode ${response.statusCode}): $detail');
    } on TimeoutException {
      return (success: false, message: 'Waktu tunggu habis. Cek koneksi internet perangkat.');
    } catch (e) {
      return (success: false, message: 'Gagal terhubung: $e');
    }
  }

  /// Menguji sederet API key secara berurutan dan berhenti pada key
  /// pertama yang berhasil — mencerminkan strategi fallback otomatis yang
  /// sama seperti saat pemindaian struk berlangsung.
  Future<({bool success, String message})> testApiKeys(List<String> apiKeys, {required AIProvider provider, required String model}) async {
    final keys = apiKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) {
      return (success: false, message: 'Belum ada API key yang diisi.');
    }
    String lastMessage = '';
    for (var i = 0; i < keys.length; i++) {
      final result = await testApiKey(keys[i], provider: provider, model: model);
      if (result.success) {
        final label = keys.length > 1 ? ' (API key ke-${i + 1} dari ${keys.length})' : '';
        return (success: true, message: '${result.message}$label');
      }
      lastMessage = 'API key ke-${i + 1}: ${result.message}';
    }
    return (success: false, message: 'Semua API key gagal diverifikasi. $lastMessage');
  }

  /// Mengambil daftar model yang BENAR-BENAR tersedia untuk API key yang
  /// dipasang, langsung dari API provider terkait (bukan daftar hardcode
  /// di kode aplikasi). Ini memastikan pilihan model di dropdown Pengaturan
  /// AI Scan selalu akurat sesuai akses API key milik pengguna saat ini.
  Future<({bool success, String message, List<String> models})> fetchAvailableModels(String apiKey, {required AIProvider provider}) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return (success: false, message: 'API key masih kosong.', models: <String>[]);
    }
    try {
      if (provider == AIProvider.groq) {
        return await _fetchGroqModels(trimmed);
      }
      return await _fetchGeminiModels(trimmed);
    } on TimeoutException {
      return (success: false, message: 'Waktu tunggu habis. Cek koneksi internet perangkat.', models: <String>[]);
    } catch (e) {
      return (success: false, message: 'Gagal mengambil daftar model: $e', models: <String>[]);
    }
  }

  Future<({bool success, String message, List<String> models})> _fetchGeminiModels(String apiKey) async {
    final response = await http
        .get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        detail = (decoded['error']?['message'] as String?) ?? response.body;
      } catch (_) {}
      return (success: false, message: 'Gagal (kode ${response.statusCode}): $detail', models: <String>[]);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawModels = decoded['models'] as List? ?? [];
    final names = <String>[];
    for (final m in rawModels) {
      final map = m as Map<String, dynamic>;
      final methods = (map['supportedGenerationMethods'] as List?)?.cast<String>() ?? [];
      if (!methods.contains('generateContent')) continue;
      final fullName = map['name'] as String? ?? '';
      final shortName = fullName.startsWith('models/') ? fullName.substring(7) : fullName;
      if (shortName.isEmpty) continue;
      // Model embedding/AQA tidak bisa membaca gambar struk, jadi disaring
      // dari daftar pilihan karena tidak relevan untuk fitur ini.
      final lower = shortName.toLowerCase();
      if (lower.contains('embedding') || lower.contains('aqa')) continue;
      names.add(shortName);
    }
    names.sort();
    if (names.isEmpty) {
      return (success: false, message: 'Tidak ada model yang cocok ditemukan untuk API key ini.', models: <String>[]);
    }
    return (success: true, message: 'Ditemukan ${names.length} model.', models: names);
  }

  Future<({bool success, String message, List<String> models})> _fetchGroqModels(String apiKey) async {
    final response = await http.get(
      Uri.parse('https://api.groq.com/openai/v1/models'),
      headers: {'Authorization': 'Bearer $apiKey'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        detail = (decoded['error']?['message'] as String?) ?? response.body;
      } catch (_) {}
      return (success: false, message: 'Gagal (kode ${response.statusCode}): $detail', models: <String>[]);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawModels = (decoded['data'] as List? ?? [])
        .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    // Groq tidak menandai kapabilitas vision di API daftar model, jadi
    // model yang dikenal mendukung gambar (mengandung "vision", "llama-4",
    // atau "llava") diprioritaskan tampil di atas; sisanya tetap
    // ditampilkan di bawahnya kalau-kalau ada model vision baru.
    bool looksVision(String id) {
      final lower = id.toLowerCase();
      return lower.contains('vision') || lower.contains('llama-4') || lower.contains('llava');
    }
    final visionModels = rawModels.where(looksVision).toList()..sort();
    final otherModels = rawModels.where((id) => !looksVision(id)).toList()..sort();
    final ordered = [...visionModels, ...otherModels];
    if (ordered.isEmpty) {
      return (success: false, message: 'Tidak ada model ditemukan untuk API key ini.', models: <String>[]);
    }
    return (success: true, message: 'Ditemukan ${ordered.length} model (model vision diutamakan di atas).', models: ordered);
  }

  Future<ReceiptScanResult> scan(File imageFile, {required bool onlineEnabled, required AIProvider provider, required List<String> apiKeys, required String model}) async {
    // AI online dicoba LEBIH DULU kalau tersedia (minimal satu API key &
    // model terisi serta fitur diaktifkan) karena umumnya jauh lebih
    // akurat membaca struk yang buram/miring dibanding OCR on-device. OCR
    // offline hanya dipakai sebagai fallback: saat semua API key online
    // gagal dipanggil (mis. tidak ada koneksi internet) atau hasilnya
    // tidak yakin.
    final hasKeys = apiKeys.any((k) => k.trim().isNotEmpty);
    if (onlineEnabled && hasKeys && model.trim().isNotEmpty) {
      final onlineResult = await scanOnline(imageFile, provider: provider, apiKeys: apiKeys, model: model);
      if (onlineResult != null && onlineResult.confident) return onlineResult;
      final offlineResult = await scanOffline(imageFile);
      if (offlineResult.confident) return offlineResult;
      return onlineResult ?? offlineResult;
    }
    return scanOffline(imageFile);
  }
}

Future<void> _pickReceiptImage(BuildContext context, ImageSource source) async {
  final file = await pickImageFileWithNativeChooser(source);
  if (file == null || !context.mounted) return;
  Navigator.push(
    context,
    GlassPageRoute(builder: (_) => ReceiptScanPage(initialImageFile: file)),
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
    final provider = ref.read(aiProviderProvider);
    final apiKeys = provider == AIProvider.groq ? ref.read(groqApiKeysProvider) : ref.read(geminiApiKeysProvider);
    final model = provider == AIProvider.groq ? ref.read(groqModelProvider) : ref.read(geminiModelProvider);
    final onlineEnabled = ref.read(receiptOnlineFallbackEnabledProvider);
    final providerLabel = provider == AIProvider.groq ? 'Groq' : 'Gemini';
    final hasKeys = apiKeys.any((k) => k.trim().isNotEmpty);
    // Kalau AI online tersedia (aktif, minimal satu API key & model
    // terisi), itu yang dicoba duluan — biasanya jauh lebih akurat
    // daripada OCR on-device. OCR offline jadi fallback kalau semua API
    // key online gagal dipanggil (mis. tidak ada koneksi internet) atau
    // hasilnya tidak yakin.
    final tryOnlineFirst = onlineEnabled && hasKeys && model.trim().isNotEmpty;
    setState(() {
      _imageFile = file;
      _result = null;
      _scanning = true;
      _scanStage = tryOnlineFirst ? 'Membaca struk dengan AI online ($providerLabel)...' : 'Membaca teks struk (offline)...';
    });
    ReceiptScanResult finalResult;
    if (tryOnlineFirst) {
      final onlineResult = await _service.scanOnline(file, provider: provider, apiKeys: apiKeys, model: model);
      if (onlineResult != null && onlineResult.confident) {
        finalResult = onlineResult;
      } else {
        if (mounted) {
          setState(() => _scanStage = onlineResult == null
              ? 'AI online tidak tersedia (cek koneksi internet/model), mencoba pemindaian offline...'
              : 'Hasil AI online kurang yakin, mencoba pemindaian offline...');
        }
        final offlineResult = await _service.scanOffline(file);
        finalResult = offlineResult.confident ? offlineResult : (onlineResult ?? offlineResult);
      }
    } else {
      finalResult = await _service.scanOffline(file);
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
    final file = await pickImageFileWithNativeChooser(source);
    if (file == null) return;
    await _runScan(file);
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
      if (!result.confident) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(context.isDark ? 0.14 : 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nominal & nama toko tidak terbaca otomatis. Silakan isi manual di bawah, atau aktifkan AI online agar pembacaan lebih akurat.',
                    style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.4),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, GlassPageRoute(builder: (_) => const ReceiptScanApiKeySettingsPage())),
                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                  label: const Text('Buka Pengaturan AI Scan', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
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
  late List<TextEditingController> _geminiKeyControllers;
  late List<TextEditingController> _groqKeyControllers;
  String? _geminiSelectedModel;
  String? _groqSelectedModel;
  List<String> _geminiModels = [];
  List<String> _groqModels = [];
  bool _obscure = true;
  bool _fetchingModels = false;
  bool _testing = false;
  bool? _testSuccess;
  String? _testMessage;
  bool? _modelsSuccess;
  String? _modelsMessage;

  @override
  void initState() {
    super.initState();
    _geminiKeyControllers = _buildControllers(ref.read(geminiApiKeysProvider));
    _groqKeyControllers = _buildControllers(ref.read(groqApiKeysProvider));
    _geminiSelectedModel = _nullIfEmpty(ref.read(geminiModelProvider));
    _groqSelectedModel = _nullIfEmpty(ref.read(groqModelProvider));
    // Kalau API key sudah pernah disimpan sebelumnya, langsung coba muat
    // daftar modelnya begitu halaman dibuka, supaya dropdown tidak kosong
    // saat pengguna kembali ke halaman ini.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstNonEmptyKey(_activeKeyControllers) != null) _fetchModels();
    });
  }

  List<TextEditingController> _buildControllers(List<String> keys) {
    if (keys.isEmpty) return [TextEditingController()];
    return keys.map((k) => TextEditingController(text: k)).toList();
  }

  String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  String? _firstNonEmptyKey(List<TextEditingController> controllers) {
    for (final c in controllers) {
      final v = c.text.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  List<String> _nonEmptyKeys(List<TextEditingController> controllers) =>
      controllers.map((c) => c.text.trim()).where((v) => v.isNotEmpty).toList();

  @override
  void dispose() {
    for (final c in _geminiKeyControllers) {
      c.dispose();
    }
    for (final c in _groqKeyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _activeKeyControllers =>
      ref.read(aiProviderProvider) == AIProvider.groq ? _groqKeyControllers : _geminiKeyControllers;
  List<String> get _activeModels =>
      ref.read(aiProviderProvider) == AIProvider.groq ? _groqModels : _geminiModels;
  String? get _activeSelectedModel =>
      ref.read(aiProviderProvider) == AIProvider.groq ? _groqSelectedModel : _geminiSelectedModel;
  set _activeSelectedModel(String? value) {
    if (ref.read(aiProviderProvider) == AIProvider.groq) {
      _groqSelectedModel = value;
    } else {
      _geminiSelectedModel = value;
    }
  }

  void _addKeyField() {
    setState(() => _activeKeyControllers.add(TextEditingController()));
  }

  void _removeKeyField(int index) {
    final controllers = _activeKeyControllers;
    if (index < 0 || index >= controllers.length) return;
    if (controllers.length <= 1) {
      // Selalu sisakan minimal satu kolom input agar pengguna tetap bisa
      // mengisi API key baru tanpa perlu menambah field terlebih dahulu.
      controllers[index].clear();
      setState(() {});
      return;
    }
    setState(() => controllers.removeAt(index).dispose());
  }

  void _selectProvider(AIProvider provider) {
    ref.read(aiProviderProvider.notifier).state = provider;
    ref.read(prefsProvider).setString('ai_provider', provider == AIProvider.groq ? 'groq' : 'gemini');
    setState(() {
      _testSuccess = null;
      _testMessage = null;
      _modelsSuccess = null;
      _modelsMessage = null;
    });
  }

  Future<void> _fetchModels() async {
    final provider = ref.read(aiProviderProvider);
    final key = _firstNonEmptyKey(_activeKeyControllers);
    if (key == null) {
      setState(() {
        _modelsSuccess = false;
        _modelsMessage = 'Masukkan minimal satu API key terlebih dahulu.';
      });
      return;
    }
    setState(() {
      _fetchingModels = true;
      _modelsSuccess = null;
      _modelsMessage = null;
    });
    final result = await ReceiptScannerService().fetchAvailableModels(key, provider: provider);
    if (!mounted) return;
    setState(() {
      _fetchingModels = false;
      _modelsSuccess = result.success;
      _modelsMessage = result.message;
      if (result.success) {
        if (provider == AIProvider.groq) {
          _groqModels = result.models;
          if (_groqSelectedModel == null || !_groqModels.contains(_groqSelectedModel)) {
            _groqSelectedModel = _groqModels.first;
          }
        } else {
          _geminiModels = result.models;
          if (_geminiSelectedModel == null || !_geminiModels.contains(_geminiSelectedModel)) {
            _geminiSelectedModel = _geminiModels.first;
          }
        }
      }
    });
  }

  void _save() {
    final provider = ref.read(aiProviderProvider);
    final keys = _nonEmptyKeys(_activeKeyControllers);
    final modelValue = _activeSelectedModel ?? '';
    if (provider == AIProvider.groq) {
      ref.read(groqApiKeysProvider.notifier).setAll(keys);
      ref.read(prefsProvider).setString('groq_model', modelValue);
      ref.read(groqModelProvider.notifier).state = modelValue;
    } else {
      ref.read(geminiApiKeysProvider.notifier).setAll(keys);
      ref.read(prefsProvider).setString('gemini_model', modelValue);
      ref.read(geminiModelProvider.notifier).state = modelValue;
    }
    showGlassSnackBar(context, keys.isEmpty ? 'Pengaturan disimpan (belum ada API key terisi)' : 'API key & model disimpan', icon: Icons.check_circle_outline);
  }

  Future<void> _testApiKey() async {
    final provider = ref.read(aiProviderProvider);
    final model = _activeSelectedModel;
    final keys = _nonEmptyKeys(_activeKeyControllers);
    if (keys.isEmpty) {
      showGlassSnackBar(context, 'Masukkan minimal satu API key terlebih dahulu', icon: Icons.warning_amber_rounded);
      return;
    }
    if (model == null) {
      showGlassSnackBar(context, 'Muat & pilih model terlebih dahulu', icon: Icons.warning_amber_rounded);
      return;
    }
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testMessage = null;
    });
    final result = await ReceiptScannerService().testApiKeys(
      keys,
      provider: provider,
      model: model,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSuccess = result.success;
      _testMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final onlineEnabled = ref.watch(receiptOnlineFallbackEnabledProvider);
    final aiProvider = ref.watch(aiProviderProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final providerLabel = aiProvider == AIProvider.groq ? 'Groq' : 'Gemini';
    final models = _activeModels;
    final selectedModel = _activeSelectedModel;
    final activeControllers = _activeKeyControllers;
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _SettingsSectionCard(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Gunakan AI Online', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                          const SizedBox(height: 4),
                          Text('AI online dicoba lebih dahulu untuk hasil pembacaan yang lebih akurat. Apabila tidak dapat diakses, sistem otomatis beralih ke pemindaian OCR offline.', style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      GlassSwitch(
                        value: onlineEnabled,
                        activeColor: primary,
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
                  const _SectionLabel('PROVIDER AI'),
                  const SizedBox(height: 10),
                  LiquidGlass(
                    borderRadius: 24,
                    useBlur: true,
                    blur: 14,
                    intensity: isDark ? 1.5 : 1.0,
                    borderColor: isDark ? context.borderColor : null,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: GlassSegmentedControl(
                        segments: [GlassSegment(label: 'Gemini'), GlassSegment(label: 'Groq')],
                        selectedIndex: aiProvider == AIProvider.groq ? 1 : 0,
                        indicatorColor: primary.withOpacity(isDark ? 0.25 : 0.15),
                        onSegmentSelected: (index) => _selectProvider(index == 1 ? AIProvider.groq : AIProvider.gemini),
                        quality: GlassQuality.premium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('$providerLabel API KEY & MODEL'),
                  const SizedBox(height: 10),
                  _SettingsSectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('API Key', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _obscure = !_obscure),
                          behavior: HitTestBehavior.opaque,
                          child: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: context.iconMuted),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Tambahkan lebih dari satu API key agar pemindaian tetap berjalan otomatis dengan key berikutnya apabila salah satu key mencapai batas kuota.',
                        style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      ...List.generate(activeControllers.length, (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Expanded(
                                child: TextField(
                                  key: ValueKey('key_field_${aiProvider.name}_$i'),
                                  controller: activeControllers[i],
                                  obscureText: _obscure,
                                  decoration: InputDecoration(labelText: 'API key ${i + 1}', isDense: true),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _removeKeyField(i),
                                icon: Icon(Icons.close_rounded, size: 18, color: context.iconMuted),
                                tooltip: 'Hapus API key ${i + 1}',
                              ),
                            ]),
                          )),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addKeyField,
                          icon: Icon(SolarIconsOutline.addCircle, size: 16, color: primary),
                          label: Text('Tambah API key', style: TextStyle(color: primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Divider(color: context.borderColor),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: models.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text('Daftar model belum dimuat', style: TextStyle(fontSize: 13, color: context.textFaint)),
                                )
                              : DropdownButtonFormField<String>(
                                  key: ValueKey('model_dropdown_${aiProvider.name}'),
                                  value: selectedModel,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Model'),
                                  items: models.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
                                  onChanged: (v) => setState(() => _activeSelectedModel = v),
                                ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _fetchingModels ? null : _fetchModels,
                          child: Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(isDark ? 0.18 : 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _fetchingModels
                                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                                : Icon(Icons.sync_rounded, color: primary, size: 20),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Perbarui daftar model yang tersedia sesuai akses API key Anda saat ini di $providerLabel.',
                        style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                      ),
                      if (_modelsMessage != null) ...[
                        const SizedBox(height: 10),
                        _InlineStatusMessage(success: _modelsSuccess == true, message: _modelsMessage!),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Seluruh API key dan model tersimpan secara lokal di perangkat ini serta hanya dikirim langsung ke penyedia AI yang dipilih saat proses pemindaian berlangsung.',
                      style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _testApiKey,
                          icon: _testing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_tethering_rounded, size: 18),
                          label: const Text('Tes Koneksi'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(onPressed: _save, child: const Text('Simpan')),
                      ),
                    ],
                  ),
                  if (_testMessage != null) ...[
                    const SizedBox(height: 14),
                    _InlineStatusMessage(success: _testSuccess == true, message: _testMessage!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2));
}

class _SettingsSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SettingsSectionCard({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
      child: child,
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  final bool success;
  final String message;
  const _InlineStatusMessage({required this.success, required this.message});
  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF24A148) : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(success ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.textPrimary))),
        ],
      ),
    );
  }
}
