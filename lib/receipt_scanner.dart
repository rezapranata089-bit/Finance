import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:http/http.dart' as http;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class ReceiptLineItem {
  final String name;
  final double? quantity;
  final double? price;
  const ReceiptLineItem({required this.name, this.quantity, this.price});

  factory ReceiptLineItem.fromJson(Map<String, dynamic> json) => ReceiptLineItem(
        name: (json['name'] as String? ?? '').trim(),
        quantity: (json['qty'] as num?)?.toDouble() ?? (json['quantity'] as num?)?.toDouble(),
        price: (json['price'] as num?)?.toDouble() ?? (json['subtotal'] as num?)?.toDouble(),
      );
}

class ReceiptScanResult {
  final String? merchant;
  final DateTime? date;
  final double? total;
  final String rawText;
  final ReceiptScanSource source;
  final bool confident;
  final List<ReceiptLineItem> items;

  const ReceiptScanResult({
    this.merchant,
    this.date,
    this.total,
    required this.rawText,
    required this.source,
    required this.confident,
    this.items = const [],
  });
}

class ReceiptParser {
  static final _totalKeywords = [
    'grand total', 'total belanja', 'total bayar', 'total tagihan',
    'total pembayaran', 'jumlah bayar', 'total transaksi', 'jumlah harus dibayar',
    'total', 'jumlah',
  ];

  // Baris yang mengandung salah satu kata ini TIDAK PERNAH dianggap sebagai
  // baris "Total", baik lewat keyword match maupun fallback nominal
  // terbesar. Tanpa ini, baris "Tunai" (uang yang dibayarkan pelanggan,
  // biasanya >= total) atau "Kembali" (kembalian) bisa salah terambil
  // sebagai total kalau urutan baris hasil OCR tidak persis mengikuti
  // urutan visual struk (umum terjadi pada foto struk yang miring/tidak
  // rata).
  static const _excludedFromTotalWords = ['tunai', 'kembali', 'kembalian', 'cash', 'change'];

  // Kata kunci yang menandai baris BUKAN item barang (baris total, bayar,
  // header toko, dll). Dipakai juga oleh matcher fuzzy di bawah supaya
  // typo hasil OCR pada kata-kata ini tetap terdeteksi.
  static const _itemExclusionKeywords = [
    'total', 'subtotal', 'sub total', 'tunai', 'kembali', 'cash', 'change',
    'bayar', 'diskon', 'discount', 'pajak', 'ppn', 'tax', 'service',
    'points', 'poin', 'kasir', 'cashier', 'no. transaksi', 'struk', 'invoice',
    'npwp', 'telp', 'terima kasih', 'jumlah',
  ];

  // Levenshtein distance sederhana, dipakai untuk mentolerir typo hasil OCR
  // pada kata kunci pendek (mis. "Kembali" yang terbaca "Kenbali", "Total"
  // yang terbaca "Totai"). Tanpa toleransi ini, kata kunci exclusion gagal
  // match hanya karena satu huruf salah baca, dan baris kembalian bisa
  // lolos tertangkap sebagai nominal total atau nama item.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  // Toleransi typo OCR pada level kata: kata kunci panjang (>=9 huruf)
  // boleh beda hingga 2 karakter, selebihnya hanya boleh beda 1 karakter —
  // cukup untuk menutupi typo umum tanpa salah menangkap kata lain yang
  // kebetulan mirip (mis. "tomat" tidak boleh ikut ke-exclude gara-gara
  // mirip "total").
  static bool _lineMatchesKeyword(String line, String keyword) {
    final lower = line.toLowerCase();
    if (lower.contains(keyword)) return true;
    if (keyword.contains(' ')) return false;
    final maxDist = keyword.length >= 9 ? 2 : 1;
    final words = lower.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      if ((w.length - keyword.length).abs() > maxDist) continue;
      if (_levenshtein(w, keyword) <= maxDist) return true;
    }
    return false;
  }

  static bool _isExcludedTotalLine(String line) {
    return _excludedFromTotalWords.any((w) => _lineMatchesKeyword(line, w));
  }

  static bool _looksLikeItemExcluded(String line) {
    return _itemExclusionKeywords.any((w) => _lineMatchesKeyword(line, w));
  }

  static final _amountRegex = RegExp(
    r'(?:rp\.?\s*)?([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?|[0-9]{4,})',
    caseSensitive: false,
  );

  // Struk thermal yang buram/miring sering membuat OCR menyisipkan tanda
  // pemisah ganda berurutan di tengah angka (mis. "54.,500,00" yang
  // seharusnya "54.500,00"). Tanpa dibersihkan lebih dulu, angka seperti
  // ini gagal cocok sama sekali dengan _amountRegex sehingga baris "Total"
  // dianggap tidak mengandung nominal apa pun.
  static String _cleanNumericNoise(String text) {
    return text.replaceAllMapped(RegExp(r'(\d)[.,]{2,}(\d)'), (m) => '${m.group(1)}.${m.group(2)}');
  }

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

  // Baris yang tampak seperti rincian item (mengandung pola qty x harga =
  // subtotal, atau minimal diakhiri "= nominal"), dipakai untuk memvalidasi
  // kewajaran total & sebagai cadangan kalau baris "Total" gagal terbaca.
  static bool _looksLikeItemAmountLine(String line) {
    return RegExp(r'[xX]\s*[\d.,]+\s*=').hasMatch(line) || RegExp(r'=\s*[\d.,\-—\s]+$').hasMatch(line);
  }

  static double? parseTotal(String text) {
    final cleanedText = _cleanNumericNoise(text);
    final lines = cleanedText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    double? keywordTotal;
    for (final keyword in _totalKeywords) {
      for (final line in lines) {
        if (_isExcludedTotalLine(line)) continue;
        if (_lineMatchesKeyword(line, keyword)) {
          final amount = _extractAmount(line);
          if (amount != null && amount > 0) {
            keywordTotal = amount;
            break;
          }
        }
      }
      if (keywordTotal != null) break;
    }

    final itemAmounts = <double>[];
    for (final line in lines) {
      if (_isExcludedTotalLine(line) || _looksLikeItemExcluded(line)) continue;
      if (_looksLikeItemAmountLine(line)) {
        final amt = _extractAmount(line);
        if (amt != null && amt > 0) itemAmounts.add(amt);
      }
    }
    final sumItems = itemAmounts.fold<double>(0, (a, b) => a + b);

    // Nominal "Total" hasil OCR kadang meleset jauh (mis. baris kembalian
    // ikut terbaca sebagai baris total karena kata kuncinya typo). Kalau
    // nilainya jauh di luar kewajaran dibanding jumlah rincian item yang
    // berhasil terbaca, lebih percaya jumlah item daripada angka yang
    // meleset itu.
    bool implausible(double candidate) =>
        sumItems > 0 && candidate > sumItems * 20 && (candidate - sumItems) > 100000;

    if (keywordTotal != null) {
      return implausible(keywordTotal) ? sumItems : keywordTotal;
    }

    double? largest;
    for (final line in lines) {
      if (_isExcludedTotalLine(line)) continue;
      final amount = _extractAmount(line);
      if (amount != null && (largest == null || amount > largest)) largest = amount;
    }
    if (largest != null && implausible(largest)) return sumItems;
    return largest ?? (sumItems > 0 ? sumItems : null);
  }

  // (?<!\d) dan (?!\d) mengunci batas angka: mencegah regex "mencuil"
  // sebagian digit dari tengah angka yang lebih panjang (mis. tanpa ini,
  // "2023-08-02" bisa salah kebaca sebagai "23-08-02" lalu disangka
  // format DD-MM-YY → 23 Agustus 2002, alih-alih 2 Agustus 2023).
  static final List<RegExp> _dateRegexes = [
    RegExp(r'(?<!\d)(\d{1,2})\s*[\/\-\.]\s*(\d{1,2})\s*[\/\-\.]\s*(\d{2,4})(?!\d)'),
    RegExp(r'(?<!\d)(\d{4})\s*[\/\-\.]\s*(\d{1,2})\s*[\/\-\.]\s*(\d{1,2})(?!\d)'),
  ];

  // Fallback untuk format tanggal dengan nama bulan (mis. "24 Agu 2026",
  // "24-Agustus-2026") yang tidak tertangkap pola numerik di atas — ini
  // penyebab paling umum tanggal sudah terbaca di rawText tapi field
  // tanggal di form tetap kosong.
  static const Map<String, int> _monthNames = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'mei': 5, 'may': 5, 'jun': 6,
    'jul': 7, 'agu': 8, 'ags': 8, 'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10,
    'nov': 11, 'des': 12, 'dec': 12,
  };

  static final RegExp _monthNameDateRegex = RegExp(
    r'(?<!\d)(\d{1,2})\s*[\/\-\.\s]\s*([A-Za-z]{3,9})\s*[\/\-\.\s]\s*(\d{2,4})(?!\d)',
  );

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
    final monthMatch = _monthNameDateRegex.firstMatch(text);
    if (monthMatch != null) {
      final day = int.tryParse(monthMatch.group(1)!);
      final rawMonth = monthMatch.group(2)!.toLowerCase();
      final monthKey = rawMonth.length >= 3 ? rawMonth.substring(0, 3) : rawMonth;
      final month = _monthNames[monthKey];
      final yearRaw = int.tryParse(monthMatch.group(3)!);
      if (day != null && month != null && yearRaw != null) {
        final year = yearRaw < 100 ? 2000 + yearRaw : yearRaw;
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }
    return null;
  }

  // Simbol noise umum hasil OCR (garis pemisah struk yang terbaca sebagai
  // tanda minus/pipe/kutip, dsb.) yang sering menempel di awal/akhir baris
  // dan membuat baris judul (mis. nama toko) ikut kebawa kotor seperti
  // "- Sal:" alih-alih "Sal:".
  static final RegExp _lineNoiseEdges = RegExp(r'^[\-\*\|_~":;.,\s]+|[\-\*\|_~":;.,\s]+$');

  static String? parseMerchant(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (final rawLine in lines.take(6)) {
      final line = rawLine.replaceAll(_lineNoiseEdges, '').trim();
      if (line.isEmpty) continue;
      final letters = line.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      // Butuh cukup huruf DAN mayoritas karakter baris berupa huruf (bukan
      // simbol acak hasil noise OCR seperti '"l;t-:;').
      if (letters.length >= 3 && letters.length / line.length >= 0.5) return line;
    }
    if (lines.isNotEmpty) {
      final cleaned = lines.first.replaceAll(_lineNoiseEdges, '').trim();
      return cleaned.isEmpty ? lines.first : cleaned;
    }
    return null;
  }

  // Baris bernomor urut (mis. "1. Indomie Goreng") dianggap AWAL blok
  // item, karena pada banyak struk kasir offline nama barang dan baris
  // qty/harga berada di baris TERPISAH (bukan satu baris seperti asumsi
  // lama). Semua baris di antara satu nomor urut sampai nomor urut
  // berikutnya (atau sampai baris kata kunci total/pembayaran) dipindai
  // untuk mencari harga (nominal terbesar yang muncul) & qty, lalu
  // digabung jadi satu item.
  static final RegExp _itemBulletRegex = RegExp(r'^(\d{1,3})\s*[.\):]\s+(.+)$');

  // Baris "harga saja": pola qty x harga = subtotal TANPA nama barang di
  // baris yang sama — sangat umum pada struk kasir warung/toko kelontong
  // yang memisahkan baris nama barang dari baris rincian harganya.
  static final RegExp _priceOnlyLineRegex = RegExp(r'^\d+\s*[xX]?\s*[\d.,]+\s*=\s*[\d.,\-—\s]*$');

  static const _unitWordsRegexPattern = r'\b(PCS|PC|PAK|PACK|BOX|BTL|LSN|LUSIN|KG|GR|GRAM|ML|LTR|L|BKS|BUAH|UNIT)\b';

  static List<ReceiptLineItem> parseItems(String text) {
    final cleanedText = _cleanNumericNoise(text);
    final lines = cleanedText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final bulletIndices = <int>[
      for (var i = 0; i < lines.length; i++)
        if (_itemBulletRegex.hasMatch(lines[i])) i,
    ];
    if (bulletIndices.isNotEmpty) {
      final bulleted = _parseItemsBulleted(lines, bulletIndices);
      if (bulleted.isNotEmpty) return bulleted;
    }
    final paired = _parseItemsPairedLines(lines);
    if (paired.isNotEmpty) return paired;
    return _parseItemsFlatFallback(lines);
  }

  static List<ReceiptLineItem> _parseItemsBulleted(List<String> lines, List<int> bulletIndices) {
    final items = <ReceiptLineItem>[];
    for (var b = 0; b < bulletIndices.length; b++) {
      final startIdx = bulletIndices[b];
      final endIdx = b + 1 < bulletIndices.length ? bulletIndices[b + 1] : lines.length;
      final name = _itemBulletRegex.firstMatch(lines[startIdx])!.group(2)!.trim();
      if (name.isEmpty) continue;
      double? price;
      double? qty;
      for (var i = startIdx + 1; i < endIdx; i++) {
        final line = lines[i];
        if (_looksLikeItemExcluded(line)) break;
        final amt = _extractAmount(line);
        if (amt != null && amt > 0 && (price == null || amt > price)) price = amt;
        if (qty == null) {
          final qtyMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*[a-zA-Z]*\s*[xX]', caseSensitive: false).firstMatch(line);
          if (qtyMatch != null) qty = double.tryParse(qtyMatch.group(1)!.replaceAll(',', '.'));
        }
      }
      if (price == null || price <= 0) continue;
      items.add(ReceiptLineItem(name: name, quantity: qty, price: price));
    }
    return items;
  }

  // Format struk tanpa penomoran, tapi nama barang & rincian harganya
  // berada di baris TERPISAH (mis. "nabati peach   PCS" lalu di baris
  // berikutnya "1 x 2000= 2.000,00"). Baris nama ditahan sebagai
  // "pendingName" sampai baris harga berikutnya ditemukan untuk dipasangkan.
  static List<ReceiptLineItem> _parseItemsPairedLines(List<String> lines) {
    final items = <ReceiptLineItem>[];
    String? pendingName;
    for (final line in lines) {
      if (_isExcludedTotalLine(line) || _looksLikeItemExcluded(line)) {
        pendingName = null;
        continue;
      }
      if (_priceOnlyLineRegex.hasMatch(line)) {
        if (pendingName != null) {
          final amt = _extractAmount(line);
          if (amt != null && amt > 0) {
            double? qty;
            final qtyMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*[xX]').firstMatch(line);
            if (qtyMatch != null) qty = double.tryParse(qtyMatch.group(1)!.replaceAll(',', '.'));
            items.add(ReceiptLineItem(name: pendingName, quantity: qty, price: amt));
          }
          pendingName = null;
        }
        continue;
      }
      final letters = line.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      final hasBigNumber = RegExp(r'\d{4,}').hasMatch(line);
      if (letters.length >= 3 && !hasBigNumber) {
        var candidate = line.replaceAll(RegExp(_unitWordsRegexPattern, caseSensitive: false), '').trim();
        pendingName = candidate.isEmpty ? line : candidate;
      }
    }
    return items;
  }

  // Fallback untuk struk yang TIDAK memakai penomoran item DAN nama+harga
  // ada dalam satu baris yang sama (format lama).
  static List<ReceiptLineItem> _parseItemsFlatFallback(List<String> lines) {
    final items = <ReceiptLineItem>[];
    for (final line in lines) {
      if (_looksLikeItemExcluded(line)) continue;
      final amount = _extractAmount(line);
      if (amount == null || amount <= 0) continue;
      var namePart = line.replaceAll(_amountRegex, '').replaceAll(RegExp(r'rp\.?', caseSensitive: false), '').trim();
      namePart = namePart.replaceAll(RegExp(r'[xX]\s*\d+$'), '').trim();
      namePart = namePart.replaceAll(RegExp(r'^[\d\.\s]+'), '').trim();
      final letters = namePart.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (namePart.isEmpty || letters.length < 3) continue;
      final qtyMatch = RegExp(r'(\d+)\s*[xX]\b').firstMatch(line);
      final qty = qtyMatch != null ? double.tryParse(qtyMatch.group(1)!) : null;
      items.add(ReceiptLineItem(name: namePart, quantity: qty, price: amount));
    }
    return items;
  }
}

class ReceiptScannerService {
  Future<ReceiptScanResult> scanOffline(File imageFile) async {
    try {
      final text = await FlutterTesseractOcr.extractText(
        imageFile.path,
        language: 'ind+eng',
        args: {
          'psm': '6',
          'preserve_interword_spaces': '1',
        },
      );
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
      final items = ReceiptParser.parseItems(text);
      return ReceiptScanResult(
        merchant: merchant,
        date: date,
        total: total,
        rawText: text,
        source: ReceiptScanSource.offline,
        confident: total != null && total > 0,
        items: items,
      );
    } catch (e) {
      // PlatformException di titik ini umumnya BUKAN bug di kode Dart,
      // melainkan Tesseract gagal diinisialisasi secara native di
      // perangkat ini (mis. tessdata belum berhasil disalin ke storage
      // aplikasi). Stack trace Java mentah tidak berguna bagi pengguna
      // awam, jadi tampilkan pesan yang lebih jelas & actionable (arahkan
      // ke fallback AI online).
      final isPlatformFailure = e is PlatformException;
      final friendlyMessage = isPlatformFailure
          ? 'Pemindaian offline tidak didukung di perangkat ini. Aktifkan "AI online" di Pengaturan > Pengaturan AI Scan agar tetap bisa memindai struk.'
          : 'Gagal memindai teks (offline): $e';
      return ReceiptScanResult(
        rawText: friendlyMessage,
        source: ReceiptScanSource.offline,
        confident: false,
      );
    }
  }

  static const String _receiptPrompt =
      'Kamu membaca foto struk belanja. Balas HANYA dengan JSON valid tanpa markdown, '
      'format persis: {"merchant": string atau null, "date": "YYYY-MM-DD" atau null, "total": number atau null, '
      '"items": [{"name": string, "qty": number atau null, "price": number atau null}]}. '
      '"merchant" adalah nama toko yang tertera pada struk. Jika nama toko TIDAK terlihat/tidak tercetak '
      'pada struk, JANGAN balas null untuk field ini — sebagai gantinya isi dengan judul singkat (maksimal '
      '5 kata, Bahasa Indonesia) yang merangkum KEBUTUHAN/KATEGORI belanja berdasarkan daftar barang yang '
      'dibeli, contoh: "Belanja Kebutuhan Dapur", "Belanja Alat Tulis", "Belanja Perlengkapan Mandi" — bukan '
      'sekadar menyebutkan nama barang satu per satu. '
      '"total" adalah jumlah akhir yang harus dibayar (grand total), dalam angka tanpa simbol mata uang. '
      '"items" adalah daftar SEMUA barang/produk yang dibeli beserta jumlah (qty) dan harga/subtotal (price) '
      'masing-masing jika terlihat pada struk; jika struk tidak memuat rincian barang, balas items sebagai array kosong.';

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
    final itemsRaw = parsed['items'] as List? ?? const [];
    final items = itemsRaw
        .whereType<Map>()
        .map((e) => ReceiptLineItem.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.name.isNotEmpty)
        .toList();
    return ReceiptScanResult(
      merchant: merchant,
      date: date,
      total: total,
      rawText: cleaned,
      source: ReceiptScanSource.online,
      confident: total != null && total > 0,
      items: items,
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

// Membuka cunning_document_scanner: pengguna memindai/mengambil struk lewat
// UI scanner bawaan (kamera ATAU impor dari galeri, keduanya sudah
// terintegrasi di dalam satu alur package ini), lalu package otomatis
// mendeteksi tepi, meluruskan (perspective correction), dan meng-crop
// hasilnya sebelum dikembalikan sebagai path gambar siap-OCR.
Future<void> _pickReceiptImage(BuildContext context) async {
  final paths = await CunningDocumentScanner.getPictures(noOfPages: 1, isGalleryImportAllowed: true);
  if (paths == null || paths.isEmpty || !context.mounted) return;
  Navigator.push(
    context,
    GlassPageRoute(builder: (_) => ReceiptScanPage(initialImageFile: File(paths.first))),
  );
}

Future<void> pickReceiptFromCameraAndPush(BuildContext context) async {
  await _pickReceiptImage(context);
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

  Future<void> _pickAndScan() async {
    final paths = await CunningDocumentScanner.getPictures(noOfPages: 1, isGalleryImportAllowed: true);
    if (paths == null || paths.isEmpty) return;
    await _runScan(File(paths.first));
  }

  // Sebelumnya menampilkan bottom sheet berisi 2 opsi (kamera/galeri).
  // cunning_document_scanner sudah menyatukan keduanya dalam satu alur UI
  // scanner-nya sendiri (isGalleryImportAllowed: true), jadi tinggal
  // langsung memanggilnya.
  void _showSourceSheet() => _pickAndScan();

  // Menggabungkan label sumber pemindaian dengan daftar belanja (jika ada)
  // menjadi satu teks catatan, supaya rincian item ikut tersimpan di
  // riwayat transaksi, bukan hanya nominal totalnya saja.
  String _buildReceiptNote() {
    final result = _result;
    final sourceLabel = result?.source == ReceiptScanSource.online ? 'AI online' : 'offline';
    final buffer = StringBuffer('Hasil pindai struk ($sourceLabel)');
    final items = result?.items ?? const [];
    if (items.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Daftar belanja:');
      for (final item in items) {
        final qtyLabel = item.quantity != null && item.quantity! > 1
            ? '${item.quantity!.toStringAsFixed(item.quantity! == item.quantity!.roundToDouble() ? 0 : 1)}x '
            : '';
        final priceLabel = item.price != null ? ' - ${rupiah(item.price!)}' : '';
        buffer.writeln('• $qtyLabel${item.name}$priceLabel');
      }
    }
    return buffer.toString().trim();
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
    ref.read(transactionsProvider.notifier).add(
          title: _titleCtrl.text.trim(),
          amount: amount,
          income: false,
          category: Strings.t(AppLang.en, 'cat_shopping'),
          note: _buildReceiptNote(),
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
      if (result.items.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Daftar belanja terdeteksi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textMuted)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: result.items.map((item) {
              final qtyLabel = item.quantity != null && item.quantity! > 0 ? '${item.quantity!.toStringAsFixed(item.quantity! == item.quantity!.roundToDouble() ? 0 : 1)}x ' : '';
              final priceLabel = item.price != null ? rupiah(item.price!) : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text('$qtyLabel${item.name}', style: TextStyle(fontSize: 12.5, color: context.textPrimary))),
                    Text(priceLabel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textMuted)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
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

  static const _geminiModelsCacheKey = 'gemini_models_cache';
  static const _groqModelsCacheKey = 'groq_models_cache';

  List<String> _loadModelsCache(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  void _saveModelsCache(String key, List<String> models) {
    ref.read(prefsProvider).setString(key, jsonEncode(models));
  }

  @override
  void initState() {
    super.initState();
    _geminiKeyControllers = _buildControllers(ref.read(geminiApiKeysProvider));
    _groqKeyControllers = _buildControllers(ref.read(groqApiKeysProvider));
    _geminiSelectedModel = _nullIfEmpty(ref.read(geminiModelProvider));
    _groqSelectedModel = _nullIfEmpty(ref.read(groqModelProvider));
    // Muat daftar model dari CACHE lokal (SharedPreferences) secara instan
    // saat halaman dibuka, bukan lewat panggilan jaringan langsung seperti
    // sebelumnya. Panggilan jaringan otomatis di initState sebelumnya itu
    // yang menyebabkan panel ini terasa freeze sesaat setiap kali pertama
    // dibuka. Sekarang dropdown langsung terisi dari cache tanpa menunggu
    // jaringan; permintaan ke jaringan hanya dijalankan otomatis kalau
    // memang belum ada cache sama sekali (mis. pengguna baru pertama kali
    // mengisi API key), atau saat pengguna menekan tombol perbarui manual.
    final prefs = ref.read(prefsProvider);
    _geminiModels = _loadModelsCache(prefs, _geminiModelsCacheKey);
    _groqModels = _loadModelsCache(prefs, _groqModelsCacheKey);
    if (_geminiSelectedModel == null && _geminiModels.isNotEmpty) _geminiSelectedModel = _geminiModels.first;
    if (_groqSelectedModel == null && _groqModels.isNotEmpty) _groqSelectedModel = _groqModels.first;
    final activeModelsEmpty = ref.read(aiProviderProvider) == AIProvider.groq ? _groqModels.isEmpty : _geminiModels.isEmpty;
    if (activeModelsEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _firstNonEmptyKey(_activeKeyControllers) != null) _fetchModels();
      });
    }
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
    final lang = ref.read(langProvider);
    final key = _firstNonEmptyKey(_activeKeyControllers);
    if (key == null) {
      setState(() {
        _modelsSuccess = false;
        _modelsMessage = Strings.t(lang, 'enter_api_key_first');
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
          _saveModelsCache(_groqModelsCacheKey, _groqModels);
        } else {
          _geminiModels = result.models;
          if (_geminiSelectedModel == null || !_geminiModels.contains(_geminiSelectedModel)) {
            _geminiSelectedModel = _geminiModels.first;
          }
          _saveModelsCache(_geminiModelsCacheKey, _geminiModels);
        }
      }
    });
  }

  void _save() {
    final provider = ref.read(aiProviderProvider);
    final lang = ref.read(langProvider);
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
    showGlassSnackBar(context, keys.isEmpty ? Strings.t(lang, 'settings_saved_no_key') : Strings.t(lang, 'api_key_model_saved'), icon: Icons.check_circle_outline);
  }

  void _showApiKeyManager() {
    final aiProvider = ref.read(aiProviderProvider);
    final lang = ref.read(langProvider);
    final providerLabel = aiProvider == AIProvider.groq ? 'Groq' : 'Gemini';
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final activeControllers = _activeKeyControllers;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Strings.t(lang, 'api_key_for_provider').replaceAll('{provider}', providerLabel), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
                      GestureDetector(
                        onTap: () {
                          setModalState(() => _obscure = !_obscure);
                          this.setState(() {});
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: context.iconMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(Strings.t(lang, 'api_key_manager_desc'), style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3)),
                  const SizedBox(height: 20),
                  ...List.generate(activeControllers.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: activeControllers[i],
                              obscureText: _obscure,
                              decoration: InputDecoration(labelText: Strings.t(lang, 'api_key_numbered').replaceAll('{n}', '${i + 1}'), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: () {
                                if (activeControllers.length <= 1) {
                                  activeControllers[i].clear();
                                } else {
                                  activeControllers.removeAt(i).dispose();
                                }
                                setModalState(() {});
                                this.setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              tooltip: Strings.t(lang, 'delete_api_key_numbered').replaceAll('{n}', '${i + 1}'),
                            ),
                          ),
                        ]),
                      )),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        activeControllers.add(TextEditingController());
                        setModalState(() {});
                        this.setState(() {});
                      },
                      icon: Icon(SolarIconsOutline.addCircle, size: 16, color: primary),
                      label: Text(Strings.t(lang, 'add_api_key'), style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _save();
                      },
                      child: Text(Strings.t(lang, 'save_api_key')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _testApiKey() async {
    final provider = ref.read(aiProviderProvider);
    final lang = ref.read(langProvider);
    final model = _activeSelectedModel;
    final keys = _nonEmptyKeys(_activeKeyControllers);
    if (keys.isEmpty) {
      showGlassSnackBar(context, Strings.t(lang, 'enter_api_key_first'), icon: Icons.warning_amber_rounded);
      return;
    }
    if (model == null) {
      showGlassSnackBar(context, Strings.t(lang, 'load_select_model_first'), icon: Icons.warning_amber_rounded);
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
    final lang = ref.watch(langProvider);
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
                  child: Text(Strings.t(lang, 'ai_settings'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
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
                          Text(Strings.t(lang, 'use_ai_online'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                          const SizedBox(height: 4),
                          Text(Strings.t(lang, 'ai_online_desc'), style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3)),
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
                  _SectionLabel(Strings.t(lang, 'ai_provider_label')),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: GlassSegmentedControl(
                      segments: [GlassSegment(label: 'Gemini'), GlassSegment(label: 'Groq')],
                      selectedIndex: aiProvider == AIProvider.groq ? 1 : 0,
                      indicatorColor: primary.withOpacity(isDark ? 0.25 : 0.15),
                      onSegmentSelected: (index) => _selectProvider(index == 1 ? AIProvider.groq : AIProvider.gemini),
                      quality: GlassQuality.premium,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(Strings.t(lang, 'api_key_model_label').replaceAll('{provider}', providerLabel)),
                  const SizedBox(height: 10),
                  _SettingsSectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(Strings.t(lang, 'api_keys_label'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary))),
                        Text(Strings.t(lang, 'keys_configured_count').replaceAll('{count}', '${_nonEmptyKeys(activeControllers).length}'), style: TextStyle(fontSize: 12, color: context.textMuted, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showApiKeyManager,
                          icon: const Icon(SolarIconsOutline.key, size: 16),
                          label: Text(Strings.t(lang, 'manage_api_key')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: context.borderColor, height: 1),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Text(Strings.t(lang, 'model_label'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimary))),
                      ]),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: models.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(Strings.t(lang, 'no_models_yet'), style: TextStyle(fontSize: 13, color: context.textFaint)),
                                )
                              : DropdownButtonFormField<String>(
                                  key: ValueKey('model_dropdown_${aiProvider.name}'),
                                  value: selectedModel,
                                  isExpanded: true,
                                  decoration: InputDecoration(labelText: Strings.t(lang, 'model_label'), isDense: true),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: _fetchingModels
                                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                                : Icon(Icons.sync_rounded, color: primary, size: 20),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        Strings.t(lang, 'update_model_list_desc').replaceAll('{provider}', providerLabel),
                        style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                      ),
                      if (_modelsMessage != null) ...[
                        const SizedBox(height: 10),
                        _InlineStatusMessage(success: _modelsSuccess == true, message: _modelsMessage!),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      Strings.t(lang, 'api_key_privacy_note'),
                      style: TextStyle(fontSize: 11.5, color: context.textFaint, height: 1.4),
                      textAlign: TextAlign.center,
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
                          label: Text(Strings.t(lang, 'test_connection')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(onPressed: _save, child: Text(Strings.t(lang, 'save'))),
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
