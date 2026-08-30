import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:number_flow_flutter/number_flow_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  VisibilityDetectorController.instance.updateInterval = const Duration(milliseconds: 100);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting('id_ID', null);
  await LiquidGlassWidgets.initialize();
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('fresh_data_reset_v2') ?? false)) {
    await prefs.remove('finance_cards');
    await prefs.remove('finance_transactions');
    await prefs.remove('user_profile');
    await prefs.remove('dummy_data_active');
    await prefs.setBool('fresh_data_reset_v2', true);
  }
  runApp(LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    child: ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const MyFinanceApp(),
    ),
  ));
}

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class UserProfile {
  final String name;
  final String? photoPath;
  final String? photoBytesBase64;
  final int photoVersion;
  const UserProfile({this.name = '', this.photoPath, this.photoBytesBase64, this.photoVersion = 0});

  bool get hasPhoto => photoPath != null || photoBytesBase64 != null;

  UserProfile copyWith({
    String? name,
    String? photoPath,
    String? photoBytesBase64,
    bool clearPhoto = false,
    int? photoVersion,
  }) =>
      UserProfile(
        name: name ?? this.name,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        photoBytesBase64: clearPhoto ? null : (photoBytesBase64 ?? this.photoBytesBase64),
        photoVersion: photoVersion ?? this.photoVersion,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'photoPath': photoPath,
        'photoBytesBase64': photoBytesBase64,
        'photoVersion': photoVersion,
      };
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        photoBytesBase64: json['photoBytesBase64'] as String?,
        photoVersion: json['photoVersion'] as int? ?? 0,
      );
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>(
  (ref) => UserProfileNotifier(ref.watch(prefsProvider)),
);

class UserProfileNotifier extends StateNotifier<UserProfile> {
  final SharedPreferences prefs;
  static const _key = 'user_profile';

  UserProfileNotifier(this.prefs) : super(_load(prefs));

  static UserProfile _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const UserProfile();
    }
  }

  void _persist() {
    prefs.setString(_key, jsonEncode(state.toJson()));
  }

  void updateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(name: trimmed);
    _persist();
  }

  Future<void> updatePhoto({String? path, Uint8List? bytes}) async {
    if (!kIsWeb && path != null) {
      final oldPath = state.photoPath;
      if (oldPath != null && oldPath != path) {
        PaintingBinding.instance.imageCache.evict(FileImage(File(oldPath)));
      }
      state = state.copyWith(photoPath: path, photoVersion: state.photoVersion + 1);
    } else if (kIsWeb && bytes != null) {
      state = state.copyWith(photoBytesBase64: base64Encode(bytes), photoVersion: state.photoVersion + 1);
    } else {
      return;
    }
    _persist();
  }

  Future<void> removePhoto() async {
    final oldPath = state.photoPath;
    if (!kIsWeb && oldPath != null) {
      PaintingBinding.instance.imageCache.evict(FileImage(File(oldPath)));
      final file = File(oldPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    state = state.copyWith(clearPhoto: true, photoVersion: state.photoVersion + 1);
    _persist();
  }
}

class ProfilePhotoPick {
  final String? path;
  final Uint8List? bytes;
  const ProfilePhotoPick({this.path, this.bytes});
}

Future<ProfilePhotoPick?> pickAndCompressProfilePhoto(ImageSource source) async {
  final picker = ImagePicker();
  final XFile? picked = await picker.pickImage(
    source: source,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 75,
  );
  if (picked == null) return null;

  if (kIsWeb) {
    final bytes = await picked.readAsBytes();
    return ProfilePhotoPick(bytes: bytes);
  }

  final dir = await getApplicationDocumentsDirectory();
  final destPath = '${dir.path}/profile_photo.jpg';
  final destFile = File(destPath);
  if (await destFile.exists()) {
    try {
      await destFile.delete();
    } catch (_) {}
  }
  await File(picked.path).copy(destPath);
  return ProfilePhotoPick(path: destPath);
}

  Future<void> showProfilePhotoOptions(BuildContext context, WidgetRef ref) async {
  final lang = ref.read(langProvider);
  final hasPhoto = ref.read(userProfileProvider).hasPhoto;
  await showModalBottomSheet(
    context: context,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t(lang, 'change_photo'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 24, color: context.textPrimary)),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(Strings.t(lang, 'choose_from_gallery')),
            onTap: () async {
              Navigator.pop(sheetContext);
              final result = await pickAndCompressProfilePhoto(ImageSource.gallery);
              if (result != null) ref.read(userProfileProvider.notifier).updatePhoto(path: result.path, bytes: result.bytes);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(Strings.t(lang, 'take_photo')),
            onTap: () async {
              Navigator.pop(sheetContext);
              final result = await pickAndCompressProfilePhoto(ImageSource.camera);
              if (result != null) ref.read(userProfileProvider.notifier).updatePhoto(path: result.path, bytes: result.bytes);
            },
          ),
          if (hasPhoto)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(Strings.t(lang, 'remove_photo'), style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(userProfileProvider.notifier).removePhoto();
              },
            ),
        ]),
      ),
    ),
  );
}

Future<void> showEditNameDialog(BuildContext context, WidgetRef ref) async {
  final lang = ref.read(langProvider);
  final nameCtrl = TextEditingController(text: ref.read(userProfileProvider).name);
  final nameShakeKey = GlobalKey<ShakeFieldState>();
  String? nameError;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.t(lang, 'edit_name'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 26, color: context.textPrimary)),
        const SizedBox(height: 18),
        ShakeField(
          key: nameShakeKey,
          child: TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Strings.t(lang, 'your_name'), errorText: nameError)),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final trimmed = nameCtrl.text.trim();
              if (trimmed.isEmpty) {
                setModalState(() => nameError = Strings.t(lang, 'field_required'));
                nameShakeKey.currentState?.shake();
                Future.delayed(const Duration(milliseconds: 3000), () {
                  if (context.mounted) setModalState(() => nameError = null);
                });
                return;
              }
              ref.read(userProfileProvider.notifier).updateName(trimmed);
              Navigator.pop(sheetContext);
            },
            child: Text(Strings.t(lang, 'save_changes')),
          ),
        ),
      ]),
    )),
  );
}

class ProfileAvatar extends StatelessWidget {
  final String? photoPath;
  final String? photoBytesBase64;
  final int photoVersion;
  final String initial;
  final double radius;
  const ProfileAvatar({
    super.key,
    required this.photoPath,
    this.photoBytesBase64,
    required this.photoVersion,
    required this.initial,
    this.radius = 31,
  });

  Widget _fallback(Color primary) => CircleAvatar(
        radius: radius,
        backgroundColor: primary,
        child: Text(initial, style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final diameter = radius * 2;
    final cacheDim = (diameter * MediaQuery.devicePixelRatioOf(context)).round();

    if (kIsWeb) {
      if (photoBytesBase64 == null) return _fallback(primary);
      Uint8List bytes;
      try {
        bytes = base64Decode(photoBytesBase64!);
      } catch (_) {
        return _fallback(primary);
      }
      return ClipOval(
        key: ValueKey('avatar-web-$photoVersion'),
        child: Image.memory(
          bytes,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          cacheWidth: cacheDim,
          cacheHeight: cacheDim,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _fallback(primary),
        ),
      );
    }

    if (photoPath == null) return _fallback(primary);
    return ClipOval(
      key: ValueKey('avatar-$photoVersion'),
      child: Image.file(
        File(photoPath!),
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        cacheWidth: cacheDim,
        cacheHeight: cacheDim,
        errorBuilder: (context, error, stackTrace) => _fallback(primary),
      ),
    );
  }
}
class AppThemePalette {
  final String name;
  final Color primary, secondary, tertiary;
  const AppThemePalette(this.name, this.primary, this.secondary, this.tertiary);
}

const appPalettes = [
  AppThemePalette('Lavender Glow', Color(0xFF7655D8), Color(0xFFD6F6A6), Color(0xFFF4EDFF)),
  AppThemePalette('Emerald City', Color(0xFF24A148), Color(0xFFD6F6A6), Color(0xFFE7F7EA)),
  AppThemePalette('Rose Petal', Color(0xFFE05270), Color(0xFFFFD8E4), Color(0xFFFBE8ED)),
  AppThemePalette('Ocean Breeze', Color(0xFF2196F3), Color(0xFFFFC107), Color(0xFFE3F2FD)),
  AppThemePalette('Sunset Vibes', Color(0xFFFF9800), Color(0xFF4CAF50), Color(0xFFFFF3E0)),
];

final tabProvider = StateProvider<int>((ref) => 0);
final selectedCardProvider = StateProvider<int>((ref) => -1);

enum CardType { normal, piutang }

class FinanceCard {
  final String number;
  final String name;
  final double initialBalance;
  final CardType type;
  const FinanceCard({required this.number, required this.name, this.initialBalance = 0, this.type = CardType.normal});

  Map<String, dynamic> toJson() => {'number': number, 'name': name, 'initialBalance': initialBalance, 'type': type.name};
  factory FinanceCard.fromJson(Map<String, dynamic> json) =>
      FinanceCard(
        number: json['number'] as String,
        name: json['name'] as String,
        initialBalance: (json['initialBalance'] as num?)?.toDouble() ?? 0,
        type: CardType.values.firstWhere((t) => t.name == json['type'], orElse: () => CardType.normal),
      );
}

final cardsProvider = StateNotifierProvider<CardsNotifier, List<FinanceCard>>(
  (ref) => CardsNotifier(ref.watch(prefsProvider)),
);

class CardsNotifier extends StateNotifier<List<FinanceCard>> {
  final SharedPreferences prefs;
  static const _key = 'finance_cards';

  CardsNotifier(this.prefs) : super(_load(prefs));

  static List<FinanceCard> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => FinanceCard.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist() {
    prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  void add(String number, String name, {double initialBalance = 0}) {
    state = [...state, FinanceCard(number: number, name: name, initialBalance: initialBalance)];
    _persist();
  }

  void update(int index, String number, String name, {double? initialBalance}) {
    if (index < 0 || index >= state.length) return;
    final list = [...state];
    list[index] = FinanceCard(number: number, name: name, initialBalance: initialBalance ?? list[index].initialBalance);
    state = list;
    _persist();
  }

  void remove(int index) {
    if (state.length <= 1 || index < 0 || index >= state.length) return;
    final list = [...state]..removeAt(index);
    state = list;
    _persist();
  }

  int ensurePiutangCard() {
    final idx = state.indexWhere((c) => c.type == CardType.piutang);
    if (idx != -1) return idx;
    state = [...state, const FinanceCard(number: '**** PTG', name: 'Kartu Piutang', initialBalance: 0, type: CardType.piutang)];
    _persist();
    return state.length - 1;
  }
}

enum LoanInterestType { flat, declining }

enum LoanStatus { active, paid, inactive }

class LoanPayment {
  final String? transactionId;
  final DateTime date;
  final double interestAmount;
  final double principalAmount;
  final String note;
  const LoanPayment({this.transactionId, required this.date, this.interestAmount = 0, this.principalAmount = 0, this.note = ''});

  Map<String, dynamic> toJson() => {
        'transactionId': transactionId,
        'date': date.toIso8601String(),
        'interestAmount': interestAmount,
        'principalAmount': principalAmount,
        'note': note,
      };

  factory LoanPayment.fromJson(Map<String, dynamic> json) => LoanPayment(
        transactionId: json['transactionId'] as String?,
        date: DateTime.parse(json['date'] as String),
        interestAmount: (json['interestAmount'] as num?)?.toDouble() ?? 0,
        principalAmount: (json['principalAmount'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String? ?? '',
      );
}

class Loan {
  final String id;
  final String borrowerName;
  final double principal;
  final double remainingPrincipal;
  final double interestPercent;
  final LoanInterestType interestType;
  final DateTime startDate;
  final LoanStatus status;
  final String note;
  final int cardIndex;
  final int sourceCardIndex;
  final List<LoanPayment> payments;

  const Loan({
    required this.id,
    required this.borrowerName,
    required this.principal,
    required this.remainingPrincipal,
    required this.interestPercent,
    required this.interestType,
    required this.startDate,
    required this.status,
    required this.cardIndex,
    required this.sourceCardIndex,
    this.note = '',
    this.payments = const [],
  });

  double get currentInterest {
    if (status != LoanStatus.active) return 0;
    final base = interestType == LoanInterestType.declining ? remainingPrincipal : principal;
    return base * interestPercent / 100;
  }

  double get totalInterestCollected => payments.fold<double>(0, (a, p) => a + p.interestAmount);

  Loan copyWith({
    String? borrowerName,
    double? principal,
    double? remainingPrincipal,
    double? interestPercent,
    LoanInterestType? interestType,
    DateTime? startDate,
    LoanStatus? status,
    String? note,
    int? cardIndex,
    int? sourceCardIndex,
    List<LoanPayment>? payments,
  }) =>
      Loan(
        id: id,
        borrowerName: borrowerName ?? this.borrowerName,
        principal: principal ?? this.principal,
        remainingPrincipal: remainingPrincipal ?? this.remainingPrincipal,
        interestPercent: interestPercent ?? this.interestPercent,
        interestType: interestType ?? this.interestType,
        startDate: startDate ?? this.startDate,
        status: status ?? this.status,
        note: note ?? this.note,
        cardIndex: cardIndex ?? this.cardIndex,
        sourceCardIndex: sourceCardIndex ?? this.sourceCardIndex,
        payments: payments ?? this.payments,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'borrowerName': borrowerName,
        'principal': principal,
        'remainingPrincipal': remainingPrincipal,
        'interestPercent': interestPercent,
        'interestType': interestType.name,
        'startDate': startDate.toIso8601String(),
        'status': status.name,
        'note': note,
        'cardIndex': cardIndex,
        'sourceCardIndex': sourceCardIndex,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
        id: json['id'] as String,
        borrowerName: json['borrowerName'] as String,
        principal: (json['principal'] as num).toDouble(),
        remainingPrincipal: (json['remainingPrincipal'] as num).toDouble(),
        interestPercent: (json['interestPercent'] as num).toDouble(),
        interestType: LoanInterestType.values.firstWhere((t) => t.name == json['interestType'], orElse: () => LoanInterestType.declining),
        startDate: DateTime.parse(json['startDate'] as String),
        status: LoanStatus.values.firstWhere((s) => s.name == json['status'], orElse: () => LoanStatus.active),
        note: json['note'] as String? ?? '',
        cardIndex: json['cardIndex'] as int? ?? 0,
        sourceCardIndex: json['sourceCardIndex'] as int? ?? 0,
        payments: (json['payments'] as List? ?? []).map((e) => LoanPayment.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

({DateTime? date, bool reached}) estimateLoanBEP(Loan loan) {
  final totalInterest = loan.totalInterestCollected;
  final remainingToBEP = loan.principal - totalInterest;
  if (remainingToBEP <= 0) return (date: null, reached: true);
  final interestPayments = loan.payments.where((p) => p.interestAmount > 0).toList()..sort((a, b) => a.date.compareTo(b.date));
  double avgInterestPerPeriod;
  double avgIntervalDays;
  if (interestPayments.length >= 2) {
    avgInterestPerPeriod = interestPayments.fold<double>(0, (a, p) => a + p.interestAmount) / interestPayments.length;
    double totalGapDays = 0;
    for (var i = 1; i < interestPayments.length; i++) {
      totalGapDays += interestPayments[i].date.difference(interestPayments[i - 1].date).inDays.abs();
    }
    avgIntervalDays = totalGapDays / (interestPayments.length - 1);
    if (avgIntervalDays <= 0) avgIntervalDays = 30;
  } else if (interestPayments.length == 1) {
    avgInterestPerPeriod = interestPayments.first.interestAmount;
    avgIntervalDays = interestPayments.first.date.difference(loan.startDate).inDays.abs().toDouble();
    if (avgIntervalDays <= 0) avgIntervalDays = 30;
  } else {
    avgInterestPerPeriod = loan.currentInterest;
    avgIntervalDays = 30;
  }
  if (avgInterestPerPeriod <= 0) return (date: null, reached: false);
  final periodsNeeded = (remainingToBEP / avgInterestPerPeriod).ceil();
  final lastDate = interestPayments.isNotEmpty ? interestPayments.last.date : loan.startDate;
  final targetDate = lastDate.add(Duration(days: (avgIntervalDays * periodsNeeded).round()));
  return (date: targetDate, reached: false);
}

final loansProvider = StateNotifierProvider<LoansNotifier, List<Loan>>(
  (ref) => LoansNotifier(ref.watch(prefsProvider), ref),
);

class LoansNotifier extends StateNotifier<List<Loan>> {
  final SharedPreferences prefs;
  final Ref ref;
  static const _key = 'finance_loans';

  LoansNotifier(this.prefs, this.ref) : super(_load(prefs));

  static List<Loan> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Loan.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist() {
    prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  void addLoan({
    required String borrowerName,
    required double principal,
    required double interestPercent,
    required LoanInterestType interestType,
    required DateTime startDate,
    required String note,
    required int sourceCardIndex,
  }) {
    final cardIndex = ref.read(cardsProvider.notifier).ensurePiutangCard();
    final loan = Loan(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      borrowerName: borrowerName,
      principal: principal,
      remainingPrincipal: principal,
      interestPercent: interestPercent,
      interestType: interestType,
      startDate: startDate,
      status: LoanStatus.active,
      note: note,
      cardIndex: cardIndex,
      sourceCardIndex: sourceCardIndex,
    );
    state = [loan, ...state];
    _persist();
    ref.read(transactionsProvider.notifier).add(
          title: 'Pinjaman ke $borrowerName',
          amount: principal,
          income: false,
          category: 'Pinjaman Diberikan',
          note: note,
          date: startDate,
          cardIndex: sourceCardIndex,
          loanId: loan.id,
        );
  }

  void updateLoan(String id, {String? borrowerName, double? principal, double? interestPercent, LoanInterestType? interestType, String? note}) {
    final idx = state.indexWhere((l) => l.id == id);
    if (idx == -1) return;
    final oldLoan = state[idx];
    double? newRemaining;
    LoanStatus? newStatus;
    final principalChanged = principal != null && principal != oldLoan.principal;
    if (principalChanged) {
      final delta = principal - oldLoan.principal;
      newRemaining = (oldLoan.remainingPrincipal + delta).clamp(0, principal).toDouble();
      if (newRemaining <= 0) {
        newStatus = LoanStatus.paid;
      } else if (oldLoan.status == LoanStatus.paid) {
        newStatus = LoanStatus.active;
      }
    }
    final list = [...state];
    list[idx] = oldLoan.copyWith(
      borrowerName: borrowerName,
      principal: principal,
      remainingPrincipal: newRemaining,
      interestPercent: interestPercent,
      interestType: interestType,
      note: note,
      status: newStatus,
    );
    state = list;
    _persist();
    final trimmedName = borrowerName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty && trimmedName != oldLoan.borrowerName) {
      ref.read(transactionsProvider.notifier).renameByLoan(id, trimmedName);
    }
    if (principalChanged) {
      ref.read(transactionsProvider.notifier).updatePrincipalAmountByLoan(id, principal);
    }
  }

  void toggleActive(String id) {
    final idx = state.indexWhere((l) => l.id == id);
    if (idx == -1) return;
    final loan = state[idx];
    if (loan.status == LoanStatus.paid) return;
    final list = [...state];
    list[idx] = loan.copyWith(status: loan.status == LoanStatus.inactive ? LoanStatus.active : LoanStatus.inactive);
    state = list;
    _persist();
  }

  void recordPayment(String id, {required bool isInterest, required double amount, required DateTime date, required String note}) {
    final idx = state.indexWhere((l) => l.id == id);
    if (idx == -1) return;
    final loan = state[idx];
    final txId = 'loantx-${DateTime.now().microsecondsSinceEpoch}';
    if (isInterest) {
      final payment = LoanPayment(transactionId: txId, date: date, interestAmount: amount, principalAmount: 0, note: note);
      final list = [...state];
      list[idx] = loan.copyWith(payments: [...loan.payments, payment]);
      state = list;
      _persist();
      ref.read(transactionsProvider.notifier).add(
            id: txId,
            title: 'Bunga · ${loan.borrowerName}',
            amount: amount,
            income: true,
            category: 'Bunga Pinjaman',
            note: note,
            date: date,
            cardIndex: loan.cardIndex,
            loanId: id,
          );
    } else {
      final newRemaining = (loan.remainingPrincipal - amount).clamp(0, loan.principal).toDouble();
      final newStatus = newRemaining <= 0 ? LoanStatus.paid : loan.status;
      final payment = LoanPayment(transactionId: txId, date: date, interestAmount: 0, principalAmount: amount, note: note);
      final list = [...state];
      list[idx] = loan.copyWith(remainingPrincipal: newRemaining, status: newStatus, payments: [...loan.payments, payment]);
      state = list;
      _persist();
      ref.read(transactionsProvider.notifier).add(
            id: txId,
            title: 'Cicilan Pokok · ${loan.borrowerName}',
            amount: amount,
            income: true,
            category: 'Cicilan Pokok',
            note: note,
            date: date,
            cardIndex: loan.sourceCardIndex,
            loanId: id,
          );
    }
  }

  void syncFromTransactionEdit(FinanceTransaction oldTx, FinanceTransaction newTx) {
    final loanId = newTx.loanId;
    if (loanId == null) return;
    final idx = state.indexWhere((l) => l.id == loanId);
    if (idx == -1) return;
    final loan = state[idx];
    if (oldTx.category == 'Pinjaman Diberikan') {
      final delta = newTx.amount - oldTx.amount;
      final newPrincipal = newTx.amount;
      final newRemaining = (loan.remainingPrincipal + delta).clamp(0, newPrincipal).toDouble();
      LoanStatus newStatus = loan.status;
      if (newRemaining <= 0) {
        newStatus = LoanStatus.paid;
      } else if (loan.status == LoanStatus.paid) {
        newStatus = LoanStatus.active;
      }
      final list = [...state];
      list[idx] = loan.copyWith(principal: newPrincipal, remainingPrincipal: newRemaining, status: newStatus);
      state = list;
      _persist();
    } else if (oldTx.category == 'Bunga Pinjaman') {
      final pIdx = loan.payments.indexWhere((p) => p.transactionId == oldTx.id);
      if (pIdx == -1) return;
      final payments = [...loan.payments];
      payments[pIdx] = LoanPayment(transactionId: payments[pIdx].transactionId, date: newTx.date, interestAmount: newTx.amount, principalAmount: 0, note: newTx.note);
      final list = [...state];
      list[idx] = loan.copyWith(payments: payments);
      state = list;
      _persist();
    } else if (oldTx.category == 'Cicilan Pokok') {
      final pIdx = loan.payments.indexWhere((p) => p.transactionId == oldTx.id);
      if (pIdx == -1) return;
      final oldPrincipalPaid = loan.payments[pIdx].principalAmount;
      final deltaPaid = newTx.amount - oldPrincipalPaid;
      final newRemaining = (loan.remainingPrincipal - deltaPaid).clamp(0, loan.principal).toDouble();
      final payments = [...loan.payments];
      payments[pIdx] = LoanPayment(transactionId: payments[pIdx].transactionId, date: newTx.date, interestAmount: 0, principalAmount: newTx.amount, note: newTx.note);
      final newStatus = newRemaining <= 0 ? LoanStatus.paid : (loan.status == LoanStatus.paid ? LoanStatus.active : loan.status);
      final list = [...state];
      list[idx] = loan.copyWith(remainingPrincipal: newRemaining, payments: payments, status: newStatus);
      state = list;
      _persist();
    }
  }

  void removePaymentByTransaction(String loanId, String transactionId) {
    final idx = state.indexWhere((l) => l.id == loanId);
    if (idx == -1) return;
    final loan = state[idx];
    final pIdx = loan.payments.indexWhere((p) => p.transactionId == transactionId);
    if (pIdx == -1) return;
    final payment = loan.payments[pIdx];
    final payments = [...loan.payments]..removeAt(pIdx);
    double newRemaining = loan.remainingPrincipal;
    if (payment.principalAmount > 0) {
      newRemaining = (loan.remainingPrincipal + payment.principalAmount).clamp(0, loan.principal).toDouble();
    }
    final newStatus = (loan.status == LoanStatus.paid && newRemaining > 0) ? LoanStatus.active : loan.status;
    final list = [...state];
    list[idx] = loan.copyWith(remainingPrincipal: newRemaining, payments: payments, status: newStatus);
    state = list;
    _persist();
  }

  void removeLoan(String id) {
    state = state.where((l) => l.id != id).toList();
    _persist();
    ref.read(transactionsProvider.notifier).removeByLoan(id);
  }
}

final onboardingProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('onboarding_done') ?? false);
final themeProvider = StateProvider<AppThemePalette>((ref) {
  final saved = ref.watch(prefsProvider).getString('app_theme_palette');
  if (saved != null) {
    final match = appPalettes.where((p) => p.name == saved);
    if (match.isNotEmpty) return match.first;
  }
  return appPalettes[0];
});
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final saved = ref.watch(prefsProvider).getString('app_theme_mode');
  return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.light);
});

enum AppLang { en, id }

final langProvider = StateProvider<AppLang>((ref) {
  final saved = ref.watch(prefsProvider).getString('app_lang');
  return saved == 'id' ? AppLang.id : AppLang.en;
});

final categoryFeatureEnabledProvider = StateProvider<bool>((ref) => ref.watch(prefsProvider).getBool('category_feature_enabled') ?? false);

final customCategoriesProvider = StateNotifierProvider<CustomCategoriesNotifier, List<String>>(
  (ref) => CustomCategoriesNotifier(ref.watch(prefsProvider)),
);

class CustomCategoriesNotifier extends StateNotifier<List<String>> {
  final SharedPreferences prefs;
  static const _key = 'custom_categories';

  CustomCategoriesNotifier(this.prefs) : super(prefs.getStringList(_key) ?? []);

  void _persist() {
    prefs.setStringList(_key, state);
  }

  void add(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty || state.contains(trimmed)) return;
    state = [...state, trimmed];
    _persist();
  }

  void remove(String category) {
    state = state.where((c) => c != category).toList();
    _persist();
  }
}

const incomeCategoryKeys = ['cat_income', 'cat_freelance', 'cat_bonus'];
const expenseCategoryKeys = ['cat_food', 'cat_shopping', 'cat_transport', 'cat_bills', 'cat_other'];
const allBuiltinCategoryKeys = ['cat_income', 'cat_freelance', 'cat_bonus', 'cat_food', 'cat_shopping', 'cat_transport', 'cat_bills', 'cat_other'];

String? builtinCategoryKeyFor(String enLabel) {
  for (final k in allBuiltinCategoryKeys) {
    if (Strings.t(AppLang.en, k) == enLabel) return k;
  }
  return null;
}

Future<String?> promptNewCategoryDialog(BuildContext context, AppLang lang) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(Strings.t(lang, 'add_category')),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: Strings.t(lang, 'category_name'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(Strings.t(lang, 'cancel'))),
        TextButton(onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()), child: Text(Strings.t(lang, 'save_changes'))),
      ],
    ),
  );
}

extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get cardColor => isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
  Color get borderColor => isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF25212E);
  Color get textMuted => isDark ? Colors.white60 : Colors.grey.shade600;
  Color get textFaint => isDark ? Colors.white38 : Colors.grey.shade500;
  Color get iconMuted => isDark ? Colors.white54 : Colors.grey;
}

class AppFormatters {
  static final NumberFormat thousands = NumberFormat('#,###', 'id_ID');
  static final DateFormat hourMinute = DateFormat('hh:mm a');
  static final DateFormat dateTimeFull = DateFormat('d MMM yyyy, hh:mm a');
  static final DateFormat dateOnly = DateFormat('d MMM yyyy');
  static final DateFormat _monthYearId = DateFormat('MMMM yyyy', 'id_ID');
  static final DateFormat _monthYearEn = DateFormat('MMMM yyyy', 'en_US');
  static final DateFormat _dateTimeMinuteId = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
  static final DateFormat _dateTimeMinuteEn = DateFormat('d MMM yyyy, HH:mm', 'en_US');

  static DateFormat monthYear(AppLang lang) => lang == AppLang.id ? _monthYearId : _monthYearEn;
  static DateFormat dateTimeMinute(AppLang lang) => lang == AppLang.id ? _dateTimeMinuteId : _dateTimeMinuteEn;

  static String rupiah(num value) => 'Rp ${thousands.format(value).replaceAll(',', '.')}';
}

class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }
    final number = int.parse(digits);
    final formatted = AppFormatters.thousands.format(number).replaceAll(',', '.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? tint;
  final double blur;
  final double intensity;
  final bool useBlur;
  final Color? borderColor;
  final double chromaticAberration;

  const LiquidGlass({super.key, required this.child, this.borderRadius = 20, this.tint, this.blur = 6, this.intensity = 1.0, this.useBlur = false, this.borderColor, this.chromaticAberration = 0.0});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final base = tint ?? Colors.white;
    final rimColor = borderColor ?? Colors.white.withOpacity(isDark ? 0.45 : 0.85);

    if (!useBlur) {
      final opacity = ((isDark ? 0.34 : 0.86) * intensity).clamp(0.0, 1.0);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withOpacity((opacity + 0.10).clamp(0.0, 1.0)),
              base.withOpacity(opacity),
            ],
          ),
          border: Border.all(color: rimColor, width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.12), blurRadius: 10, spreadRadius: -1, offset: const Offset(0, 3)),
          ],
        ),
        child: child,
      );
    }

    final glassOpacity = ((isDark ? 0.38 : 0.30) * intensity).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: rimColor, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.12), blurRadius: 10, spreadRadius: -1, offset: const Offset(0, 3)),
        ],
      ),
      child: GlassContainer(
        shape: LiquidRoundedRectangle(borderRadius: borderRadius),
        useOwnLayer: true,
        quality: GlassQuality.premium,
        settings: LiquidGlassSettings(
          glassColor: base.withOpacity(glassOpacity),
          blur: blur,
          thickness: 30,
          refractiveIndex: 1.85,
          lightIntensity: isDark ? 1.1 : 1.35,
          lightAngle: 2.4,
          ambientStrength: isDark ? 0.5 : 0.68,
          chromaticAberration: chromaticAberration,
          whitenStrength: isDark ? 0.0 : 0.4,
          saturation: 1.15,
          shadowElevation: isDark ? 1 : 4,
        ),
        child: child,
      ),
    );
  }
}

class LiquidGlassStyle {
  final LiquidGlassShape shape;
  final LiquidGlassAppearance appearance;
  final LiquidGlassRefraction refraction;

  const LiquidGlassStyle({required this.shape, required this.appearance, required this.refraction});
}

class LiquidGlassShape {
  final double cornerRadius;

  const LiquidGlassShape._(this.cornerRadius);

  static LiquidGlassShape roundedRectangle({required double cornerRadius, Color? borderColor, double? borderWidth}) {
    return LiquidGlassShape._(cornerRadius);
  }
}

class LiquidGlassAppearance {
  final Color color;
  final LiquidGlassBlur blur;
  final double saturation;

  const LiquidGlassAppearance({required this.color, required this.blur, required this.saturation});
}

class LiquidGlassBlur {
  final double sigmaX;
  final double sigmaY;

  const LiquidGlassBlur({required this.sigmaX, required this.sigmaY});
}

class LiquidGlassRefraction {
  final double distortion;
  final double distortionWidth;
  final double magnification;
  final double chromaticAberration;

  const LiquidGlassRefraction({required this.distortion, required this.distortionWidth, required this.magnification, required this.chromaticAberration});
}

class LiquidGlassShadow extends StatelessWidget {
  final double blur;
  final double opacity;
  final Offset offset;
  final double cornerRadius;
  final Widget child;

  const LiquidGlassShadow({super.key, required this.blur, required this.opacity, required this.offset, required this.cornerRadius, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cornerRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(opacity),
            blurRadius: blur,
            offset: offset,
          ),
        ],
      ),
      child: child,
    );
  }
}

class LiquidGlassLens extends StatelessWidget {
  final LiquidGlassStyle style;
  final Widget child;

  const LiquidGlassLens({super.key, required this.style, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return GlassContainer(
      shape: LiquidRoundedRectangle(borderRadius: style.shape.cornerRadius),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: LiquidGlassSettings(
        glassColor: style.appearance.color,
        blur: style.appearance.blur.sigmaX,
        saturation: style.appearance.saturation,
        thickness: 20,
        refractiveIndex: 1 + (style.refraction.magnification - 1) * 3,
        lightIntensity: isDark ? 1.1 : 1.4,
        lightAngle: 2.4,
        ambientStrength: isDark ? 0.5 : 0.7,
        chromaticAberration: style.refraction.chromaticAberration,
        shadowElevation: isDark ? 1 : 4,
      ),
      child: child,
    );
  }
}

class VisibilityAwareLottie extends StatefulWidget {
  final String asset;
  const VisibilityAwareLottie({super.key, required this.asset});

  @override
  State<VisibilityAwareLottie> createState() => _VisibilityAwareLottieState();
}

class _VisibilityAwareLottieState extends State<VisibilityAwareLottie> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final Key _visibilityKey = UniqueKey();
  bool _isVisible = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction > 0.04;
    if (visible == _isVisible) return;
    _isVisible = visible;
    if (visible) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibility,
      child: Lottie.asset(
        widget.asset,
        controller: _controller,
        onLoaded: (composition) {
          _controller.duration = composition.duration;
          if (_isVisible) _controller.repeat();
        },
        fit: BoxFit.cover,
      ),
    );
  }
}

const _shakeEase = Cubic(0.22, 1, 0.36, 1);

class ShakeField extends StatefulWidget {
  final Widget child;
  const ShakeField({super.key, required this.child});
  @override
  State<ShakeField> createState() => ShakeFieldState();
}

class ShakeFieldState extends State<ShakeField> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 6.0).chain(CurveTween(curve: _shakeEase)), weight: 80),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0).chain(CurveTween(curve: _shakeEase)), weight: 80),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0).chain(CurveTween(curve: _shakeEase)), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0).chain(CurveTween(curve: _shakeEase)), weight: 60),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void shake() => _controller.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: widget.child,
    );
  }
}

class Strings {
  static const Map<String, Map<AppLang, String>> _s = {
    'skip': {AppLang.en: 'Skip', AppLang.id: 'Lewati'},
    'onboarding_title_1': {AppLang.en: 'Manage your finances\nmore easily', AppLang.id: 'Kelola keuanganmu\nlebih mudah'},
    'onboarding_desc_1': {AppLang.en: 'Track income, expenses, and monitor your balance growth.', AppLang.id: 'Catat pemasukan, pengeluaran, dan pantau perkembangan saldo.'},
    'onboarding_title_2': {AppLang.en: 'All transactions\nin one place', AppLang.id: 'Semua transaksi\ndalam satu tempat'},
    'onboarding_desc_2': {AppLang.en: 'Keep track of your financial activity in a neater, simpler way.', AppLang.id: 'Pantau aktivitas keuangan dengan cara yang lebih rapi dan sederhana.'},
    'onboarding_title_3': {AppLang.en: 'Understand your finances', AppLang.id: 'Pahami keuanganmu'},
    'onboarding_desc_3': {AppLang.en: 'View reports to make better financial decisions.', AppLang.id: 'Lihat laporan untuk mengambil keputusan finansial yang lebih baik.'},
    'get_started': {AppLang.en: 'Get started', AppLang.id: 'Mulai sekarang'},
    'continue': {AppLang.en: 'Continue', AppLang.id: 'Lanjutkan'},
    'nav_home': {AppLang.en: 'Home', AppLang.id: 'Beranda'},
    'nav_statistic': {AppLang.en: 'Statistic', AppLang.id: 'Statistik'},
    'nav_card': {AppLang.en: 'Card', AppLang.id: 'Kartu'},
    'nav_profile': {AppLang.en: 'Profile', AppLang.id: 'Profil'},
    'my_account': {AppLang.en: 'My Account', AppLang.id: 'Akun Saya'},
    'your_balance': {AppLang.en: 'Your Balance', AppLang.id: 'Saldo Anda'},
    'saved_last_month': {AppLang.en: 'You saved {amount} last month', AppLang.id: 'Anda menghemat {amount} bulan lalu'},
    'send': {AppLang.en: 'Send', AppLang.id: 'Kirim'},
    'request': {AppLang.en: 'Request', AppLang.id: 'Minta'},
    'exchange': {AppLang.en: 'Exchange', AppLang.id: 'Tukar'},
    'more': {AppLang.en: 'More', AppLang.id: 'Lainnya'},
    'top_merchants': {AppLang.en: 'Smart Money Picks', AppLang.id: 'Pilihan Keuangan Cerdas'},
    'view_all': {AppLang.en: 'View all', AppLang.id: 'Lihat semua'},
    'discount_title': {AppLang.en: 'AI Finance Assistant', AppLang.id: 'Asisten Keuangan AI'},
    'discount_subtitle': {AppLang.en: 'Smarter money insights', AppLang.id: 'Wawasan keuangan lebih pintar'},
    'cashback_title': {AppLang.en: 'Cashback 15%', AppLang.id: 'Cashback 15%'},
    'cashback_subtitle': {AppLang.en: 'Grocery partners', AppLang.id: 'Merchant belanja'},
    'transaction_history': {AppLang.en: 'Transaction History', AppLang.id: 'Riwayat Transaksi'},
    'today': {AppLang.en: 'TODAY', AppLang.id: 'HARI INI'},
    'receive': {AppLang.en: 'Receive', AppLang.id: 'Terima'},
    'transfer': {AppLang.en: 'Transfer', AppLang.id: 'Transfer'},
    'transactions_title': {AppLang.en: 'Transactions', AppLang.id: 'Transaksi'},
    'transactions_subtitle': {AppLang.en: 'All your financial activity', AppLang.id: 'Semua aktivitas keuanganmu'},
    'search_transactions': {AppLang.en: 'Search transactions', AppLang.id: 'Cari transaksi'},
    'filter_all': {AppLang.en: 'All', AppLang.id: 'Semua'},
    'filter_income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'filter_expense': {AppLang.en: 'Expense', AppLang.id: 'Pengeluaran'},
    'reports_title': {AppLang.en: 'Reports', AppLang.id: 'Laporan'},
    'cash_flow': {AppLang.en: 'Cash flow this month', AppLang.id: 'Arus kas bulan ini'},
    'expense_by_category': {AppLang.en: 'Expenses by category', AppLang.id: 'Pengeluaran berdasarkan kategori'},
    'income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'expense': {AppLang.en: 'Expense', AppLang.id: 'Pengeluaran'},
    'savings': {AppLang.en: 'Savings', AppLang.id: 'Tabungan'},
    'profile_title': {AppLang.en: 'Profile', AppLang.id: 'Profil'},
    'view_profile': {AppLang.en: 'View profile', AppLang.id: 'Lihat profil'},
    'premium_member': {AppLang.en: 'Premium', AppLang.id: 'Premium'},
    'change_photo': {AppLang.en: 'Change profile photo', AppLang.id: 'Ubah foto profil'},
    'choose_from_gallery': {AppLang.en: 'Choose from gallery', AppLang.id: 'Pilih dari galeri'},
    'take_photo': {AppLang.en: 'Take a photo', AppLang.id: 'Ambil foto'},
    'remove_photo': {AppLang.en: 'Remove photo', AppLang.id: 'Hapus foto'},
    'edit_name': {AppLang.en: 'Edit name', AppLang.id: 'Edit nama'},
    'your_name': {AppLang.en: 'Your name', AppLang.id: 'Nama Anda'},
    'manage_account': {AppLang.en: 'Manage your finance account', AppLang.id: 'Kelola akun keuanganmu'},
    'section_finance': {AppLang.en: 'Finance', AppLang.id: 'Keuangan'},
    'savings_target': {AppLang.en: 'Savings target', AppLang.id: 'Target tabungan'},
    'category': {AppLang.en: 'Category', AppLang.id: 'Kategori'},
    'account_wallet': {AppLang.en: 'Account / Wallet', AppLang.id: 'Akun / Dompet'},
    'receivables': {AppLang.en: 'Receivables', AppLang.id: 'Piutang'},
    'section_app': {AppLang.en: 'App', AppLang.id: 'Aplikasi'},
    'appearance': {AppLang.en: 'Appearance', AppLang.id: 'Tampilan'},
    'language': {AppLang.en: 'Language', AppLang.id: 'Bahasa'},
    'notifications': {AppLang.en: 'Notifications', AppLang.id: 'Notifikasi'},
    'backup_data': {AppLang.en: 'Backup data', AppLang.id: 'Backup data'},
    'not_available': {AppLang.en: '{name} is not available yet', AppLang.id: '{name} belum tersedia'},
    'screen_mode': {AppLang.en: 'SCREEN MODE', AppLang.id: 'MODE LAYAR'},
    'light': {AppLang.en: 'Light', AppLang.id: 'Terang'},
    'dark': {AppLang.en: 'Dark', AppLang.id: 'Gelap'},
    'system': {AppLang.en: 'System', AppLang.id: 'Sistem'},
    'theme_color': {AppLang.en: 'THEME COLOR', AppLang.id: 'WARNA TEMA'},
    'add_income': {AppLang.en: 'Add income', AppLang.id: 'Tambah pemasukan'},
    'add_income_subtitle': {AppLang.en: 'Record a new income to your account', AppLang.id: 'Catat pemasukan baru ke akun Anda'},
    'add_expense': {AppLang.en: 'Add expense', AppLang.id: 'Tambah pengeluaran'},
    'add_expense_subtitle': {AppLang.en: 'Record a new expense from your account', AppLang.id: 'Catat pengeluaran baru dari akun Anda'},
    'amount': {AppLang.en: 'Amount', AppLang.id: 'Nominal'},
    'transaction_title_field': {AppLang.en: 'Transaction title', AppLang.id: 'Judul transaksi'},
    'note_optional': {AppLang.en: 'Note (optional)', AppLang.id: 'Catatan (opsional)'},
    'date': {AppLang.en: 'Date', AppLang.id: 'Tanggal'},
    'save_transaction': {AppLang.en: 'Save transaction', AppLang.id: 'Simpan transaksi'},
    'cat_income': {AppLang.en: 'Income', AppLang.id: 'Pemasukan'},
    'cat_freelance': {AppLang.en: 'Freelance', AppLang.id: 'Freelance'},
    'cat_bonus': {AppLang.en: 'Bonus', AppLang.id: 'Bonus'},
    'cat_food': {AppLang.en: 'Food', AppLang.id: 'Makanan'},
    'cat_shopping': {AppLang.en: 'Shopping', AppLang.id: 'Belanja'},
    'cat_transport': {AppLang.en: 'Transport', AppLang.id: 'Transport'},
    'cat_bills': {AppLang.en: 'Bills', AppLang.id: 'Tagihan'},
    'cat_other': {AppLang.en: 'Other', AppLang.id: 'Lainnya'},
    'field_required': {AppLang.en: 'This field is required', AppLang.id: 'Kolom ini wajib diisi'},
    'edit_income': {AppLang.en: 'Edit income', AppLang.id: 'Edit pemasukan'},
    'edit_income_subtitle': {AppLang.en: 'Update the details of this income', AppLang.id: 'Perbarui detail pemasukan ini'},
    'edit_expense': {AppLang.en: 'Edit expense', AppLang.id: 'Edit pengeluaran'},
    'edit_expense_subtitle': {AppLang.en: 'Update the details of this expense', AppLang.id: 'Perbarui detail pengeluaran ini'},
    'save_changes': {AppLang.en: 'Save changes', AppLang.id: 'Simpan perubahan'},
    'edit': {AppLang.en: 'Edit', AppLang.id: 'Edit'},
    'delete': {AppLang.en: 'Delete', AppLang.id: 'Hapus'},
    'cancel': {AppLang.en: 'Cancel', AppLang.id: 'Batal'},
    'delete_transaction_title': {AppLang.en: 'Delete transaction', AppLang.id: 'Hapus transaksi'},
    'delete_transaction_confirm': {AppLang.en: 'Delete "{title}"? This cannot be undone.', AppLang.id: 'Hapus "{title}"? Tindakan ini tidak bisa dibatalkan.'},
    'all_accounts': {AppLang.en: 'All Accounts', AppLang.id: 'Semua Akun'},
    'add_card': {AppLang.en: 'Add card', AppLang.id: 'Tambah kartu'},
    'edit_card': {AppLang.en: 'Edit card', AppLang.id: 'Edit kartu'},
    'card_name': {AppLang.en: 'Card name', AppLang.id: 'Nama kartu'},
    'last_4_digits': {AppLang.en: 'Last 4 digits', AppLang.id: '4 digit terakhir'},
    'initial_balance': {AppLang.en: 'Initial balance', AppLang.id: 'Saldo awal'},
    'save_card': {AppLang.en: 'Save card', AppLang.id: 'Simpan kartu'},
    'use_card': {AppLang.en: 'Use card', AppLang.id: 'Pakai kartu'},
    'delete_card_title': {AppLang.en: 'Delete card', AppLang.id: 'Hapus kartu'},
    'delete_card_confirm': {AppLang.en: 'Delete "{name}"?', AppLang.id: 'Hapus "{name}"?'},
    'dummy_added': {AppLang.en: 'Dummy data added for all cards', AppLang.id: 'Data dummy ditambahkan untuk semua kartu'},
    'dummy_removed': {AppLang.en: 'Dummy data removed', AppLang.id: 'Data dummy dihapus'},
    'dummy_no_cards': {AppLang.en: 'No cards available to fill dummy data', AppLang.id: 'Belum ada kartu untuk diisi data dummy'},
    'no_expenses_yet': {AppLang.en: 'No expenses yet', AppLang.id: 'Belum ada pengeluaran'},
    'loans_title': {AppLang.en: 'Loans', AppLang.id: 'Piutang'},
    'loans_subtitle': {AppLang.en: 'Manage money you lend out', AppLang.id: 'Kelola uang yang kamu pinjamkan'},
    'add_loan': {AppLang.en: 'Add loan', AppLang.id: 'Tambah pinjaman'},
    'borrower_name': {AppLang.en: 'Borrower name', AppLang.id: 'Nama peminjam'},
    'principal_amount': {AppLang.en: 'Principal amount', AppLang.id: 'Jumlah pokok pinjaman'},
    'interest_percent': {AppLang.en: 'Interest per period (%)', AppLang.id: 'Bunga per periode (%)'},
    'interest_type': {AppLang.en: 'Interest type', AppLang.id: 'Jenis bunga'},
    'interest_flat': {AppLang.en: 'Flat (from initial principal)', AppLang.id: 'Flat (dari pokok awal)'},
    'interest_declining': {AppLang.en: 'Declining (from remaining principal)', AppLang.id: 'Menurun (dari sisa pokok)'},
    'save_loan': {AppLang.en: 'Save loan', AppLang.id: 'Simpan pinjaman'},
    'loan_active': {AppLang.en: 'Active', AppLang.id: 'Aktif'},
    'loan_paid': {AppLang.en: 'Paid off', AppLang.id: 'Lunas'},
    'loan_inactive': {AppLang.en: 'Inactive', AppLang.id: 'Nonaktif'},
    'remaining_principal': {AppLang.en: 'Remaining principal', AppLang.id: 'Sisa pokok'},
    'current_interest': {AppLang.en: 'This period interest', AppLang.id: 'Bunga periode ini'},
    'record_payment': {AppLang.en: 'Record payment', AppLang.id: 'Catat pembayaran'},
    'interest_paid': {AppLang.en: 'Interest paid', AppLang.id: 'Bunga dibayar'},
    'principal_paid': {AppLang.en: 'Principal paid', AppLang.id: 'Pokok dibayar'},
    'pay_full_remaining': {AppLang.en: 'Pay off full remaining', AppLang.id: 'Lunasi sisa pokok'},
    'save_payment': {AppLang.en: 'Save payment', AppLang.id: 'Simpan pembayaran'},
    'toggle_active': {AppLang.en: 'Deactivate', AppLang.id: 'Nonaktifkan'},
    'no_loans_yet': {AppLang.en: 'No loans yet', AppLang.id: 'Belum ada pinjaman'},
    'payment_history': {AppLang.en: 'Payment history', AppLang.id: 'Riwayat pembayaran'},
    'no_payments_yet': {AppLang.en: 'No payments yet', AppLang.id: 'Belum ada pembayaran'},
    'delete_loan_title': {AppLang.en: 'Delete loan', AppLang.id: 'Hapus pinjaman'},
    'delete_loan_confirm': {AppLang.en: 'Delete loan for "{name}"? This cannot be undone.', AppLang.id: 'Hapus pinjaman "{name}"? Tindakan ini tidak bisa dibatalkan.'},
    'total_outstanding': {AppLang.en: 'Total outstanding', AppLang.id: 'Total piutang beredar'},
    'total_interest_collected': {AppLang.en: 'Total interest collected', AppLang.id: 'Total bunga terkumpul'},
    'loan_source_card': {AppLang.en: 'Funding source', AppLang.id: 'Sumber dana'},
    'select_borrower_first': {AppLang.en: 'Please select a borrower first', AppLang.id: 'Pilih peminjam terlebih dahulu'},
    'loan_date': {AppLang.en: 'Loan date', AppLang.id: 'Tanggal pinjaman'},
    'interest_payment_count': {AppLang.en: 'Interest payments', AppLang.id: 'Pembayaran bunga'},
    'target_bep': {AppLang.en: 'Target break-even', AppLang.id: 'Target BEP'},
    'target_bep_reached': {AppLang.en: 'Break-even reached', AppLang.id: 'BEP tercapai'},
    'target_bep_unavailable': {AppLang.en: 'Not enough data yet', AppLang.id: 'Belum cukup data'},
    'principal_label': {AppLang.en: 'Principal', AppLang.id: 'Pokok pinjaman'},
    'payment_interest_label': {AppLang.en: 'Interest', AppLang.id: 'Bunga'},
    'payment_principal_label': {AppLang.en: 'Principal', AppLang.id: 'Pokok'},
    'loan_edit_from_panel_notice': {AppLang.en: 'This transaction is linked to a loan. To edit or delete it, manage it from the Loans panel.', AppLang.id: 'Transaksi ini terhubung dengan pinjaman. Untuk mengedit atau menghapusnya, kelola dari panel Loans.'},
    'go_to_loans': {AppLang.en: 'Go to Loans', AppLang.id: 'Buka panel Loans'},
    'enable_category_feature': {AppLang.en: 'Enable categories', AppLang.id: 'Aktifkan kategori'},
    'enable_category_feature_desc': {AppLang.en: 'Tag transactions with a category and see spending breakdowns', AppLang.id: 'Beri label kategori pada transaksi dan lihat rincian pengeluaran'},
    'categories_list': {AppLang.en: 'CATEGORIES', AppLang.id: 'KATEGORI'},
    'add_category': {AppLang.en: 'Add category', AppLang.id: 'Tambah kategori'},
    'category_name': {AppLang.en: 'Category name', AppLang.id: 'Nama kategori'},
  };

  static String t(AppLang lang, String key) => _s[key]?[lang] ?? key;
}

class FinanceTransaction {
  final String id;
  final String title, category, note;
  final double amount;
  final bool income;
  final DateTime date;
  final int cardIndex;
  final String? loanId;
  const FinanceTransaction({
    required this.id,
    required this.title,
    required this.category,
    required this.note,
    required this.amount,
    required this.income,
    required this.date,
    this.cardIndex = 0,
    this.loanId,
    });

    Map<String, dynamic> toJson() => {
          'id': id,
          'title': title,
          'category': category,
          'note': note,
          'amount': amount,
          'income': income,
          'date': date.toIso8601String(),
          'cardIndex': cardIndex,
          'loanId': loanId,
        };

    factory FinanceTransaction.fromJson(Map<String, dynamic> json) => FinanceTransaction(
          id: json['id'] as String,
          title: json['title'] as String? ?? '',
          category: json['category'] as String? ?? '',
          note: json['note'] as String? ?? '',
          amount: (json['amount'] as num?)?.toDouble() ?? 0,
          income: json['income'] as bool? ?? false,
          date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
          cardIndex: json['cardIndex'] as int? ?? 0,
          loanId: json['loanId'] as String?,
        );
  }
  final transactionsProvider = StateNotifierProvider<TransactionNotifier, List<FinanceTransaction>>(
  (ref) => TransactionNotifier(ref.watch(prefsProvider)),
);

class TransactionNotifier extends StateNotifier<List<FinanceTransaction>> {
  final SharedPreferences prefs;
  static int _idCounter = 0;
  static const _key = 'finance_transactions';
  static String _generateId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  TransactionNotifier(this.prefs) : super(_load(prefs));

  static List<FinanceTransaction> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => FinanceTransaction.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  void _persist() {
    prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  void add({required String title, required double amount, required bool income, required String category, required String note, required DateTime date, int cardIndex = 0, String? loanId, String? id}) {
    state = [FinanceTransaction(id: id ?? _generateId(), title: title, amount: amount, income: income, category: category, note: note, date: date, cardIndex: cardIndex, loanId: loanId), ...state];
    _persist();
  }

  void update(FinanceTransaction old, FinanceTransaction updated) {
    final idx = state.indexWhere((t) => t.id == old.id);
    if (idx == -1) return;
    final list = [...state];
    list[idx] = updated;
    state = list;
    _persist();
  }

  void remove(FinanceTransaction item) {
    state = state.where((t) => t.id != item.id).toList();
    _persist();
  }

  void addAll(List<FinanceTransaction> items) {
    state = [...items, ...state];
    _persist();
  }

  void removeAll(List<FinanceTransaction> items) {
    final idsToRemove = items.map((e) => e.id).toSet();
    state = state.where((t) => !idsToRemove.contains(t.id)).toList();
    _persist();
  }

  void renameByLoan(String loanId, String newBorrowerName) {
    final list = state.map((t) {
      if (t.loanId != loanId) return t;
      String newTitle = t.title;
      if (t.title.startsWith('Pinjaman ke ')) {
        newTitle = 'Pinjaman ke $newBorrowerName';
      } else if (t.title.startsWith('Bunga · ')) {
        newTitle = 'Bunga · $newBorrowerName';
      } else if (t.title.startsWith('Cicilan Pokok · ')) {
        newTitle = 'Cicilan Pokok · $newBorrowerName';
      }
      if (newTitle == t.title) return t;
      return FinanceTransaction(
        id: t.id,
        title: newTitle,
        category: t.category,
        note: t.note,
        amount: t.amount,
        income: t.income,
        date: t.date,
        cardIndex: t.cardIndex,
        loanId: t.loanId,
      );
    }).toList();
    state = list;
    _persist();
  }

  void removeByLoan(String loanId) {
    state = state.where((t) => t.loanId != loanId).toList();
    _persist();
  }

  void updatePrincipalAmountByLoan(String loanId, double newAmount) {
    final idx = state.indexWhere((t) => t.loanId == loanId && t.category == 'Pinjaman Diberikan');
    if (idx == -1) return;
    final old = state[idx];
    final list = [...state];
    list[idx] = FinanceTransaction(
      id: old.id,
      title: old.title,
      category: old.category,
      note: old.note,
      amount: newAmount,
      income: old.income,
      date: old.date,
      cardIndex: old.cardIndex,
      loanId: old.loanId,
    );
    state = list;
    _persist();
  }
}
    final dummyDataActiveProvider = StateProvider<bool>(
      (ref) => ref.watch(prefsProvider).getBool('dummy_data_active') ?? false,
    );
    final dummyTransactionsHolderProvider = StateProvider<List<FinanceTransaction>>(
      (ref) => ref.watch(transactionsProvider).where((item) => item.id.startsWith('dummy-')).toList(),
    );

List<FinanceTransaction> _buildSmartDummyTransactions(List<FinanceCard> cards) {
  final now = DateTime.now();
  final seed = now.microsecondsSinceEpoch;
  final list = <FinanceTransaction>[];
  for (var i = 0; i < cards.length; i++) {
    final card = cards[i];
    list.addAll([
      FinanceTransaction(id: 'dummy-$seed-$i-0', title: 'Gaji Dummy · ${card.name}', category: 'Income', note: 'Data dummy', amount: 3000000 + i * 500000, income: true, date: now.subtract(Duration(days: 1, hours: i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-1', title: 'Bonus Dummy · ${card.name}', category: 'Bonus', note: 'Data dummy', amount: 750000 + i * 150000, income: true, date: now.subtract(Duration(hours: 6 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-2', title: 'Belanja Dummy · ${card.name}', category: 'Shopping', note: 'Data dummy', amount: 250000 + i * 40000, income: false, date: now.subtract(Duration(hours: 4 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-3', title: 'Makan Dummy · ${card.name}', category: 'Food', note: 'Data dummy', amount: 45000 + i * 8000, income: false, date: now.subtract(Duration(hours: 2 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-4', title: 'Transport Dummy · ${card.name}', category: 'Transport', note: 'Data dummy', amount: 25000 + i * 5000, income: false, date: now.subtract(Duration(minutes: 40 + i * 15)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-5', title: 'Tagihan Dummy · ${card.name}', category: 'Bills', note: 'Data dummy', amount: 180000 + i * 25000, income: false, date: now.subtract(Duration(days: 2 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-6', title: 'Freelance Dummy · ${card.name}', category: 'Income', note: 'Data dummy', amount: 1250000 + i * 200000, income: true, date: now.subtract(Duration(days: 3 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-7', title: 'Belanja Online Dummy · ${card.name}', category: 'Shopping', note: 'Data dummy', amount: 325000 + i * 35000, income: false, date: now.subtract(Duration(days: 4 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-8', title: 'Hiburan Dummy · ${card.name}', category: 'Entertainment', note: 'Data dummy', amount: 150000 + i * 20000, income: false, date: now.subtract(Duration(days: 5 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-9', title: 'Bonus Proyek Dummy · ${card.name}', category: 'Bonus', note: 'Data dummy', amount: 900000 + i * 125000, income: true, date: now.subtract(Duration(days: 6 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-10', title: 'Kesehatan Dummy · ${card.name}', category: 'Health', note: 'Data dummy', amount: 210000 + i * 30000, income: false, date: now.subtract(Duration(days: 7 + i)), cardIndex: i),
      FinanceTransaction(id: 'dummy-$seed-$i-11', title: 'Investasi Dummy · ${card.name}', category: 'Investment', note: 'Data dummy', amount: 500000 + i * 100000, income: false, date: now.subtract(Duration(days: 8 + i)), cardIndex: i),
    ]);
  }
  return list;
}

void toggleDummyData(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  final lang = ref.read(langProvider);
  final isActive = ref.read(dummyDataActiveProvider);
  if (isActive) {
    final dummy = ref.read(dummyTransactionsHolderProvider);
    ref.read(transactionsProvider.notifier).removeAll(dummy);
    ref.read(dummyTransactionsHolderProvider.notifier).state = [];
    ref.read(dummyDataActiveProvider.notifier).state = false;
    ref.read(prefsProvider).setBool('dummy_data_active', false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'dummy_removed'))));
  } else {
    final cards = ref.read(cardsProvider);
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'dummy_no_cards'))));
      return;
    }
    final dummy = _buildSmartDummyTransactions(cards);
    ref.read(transactionsProvider.notifier).addAll(dummy);
    ref.read(dummyTransactionsHolderProvider.notifier).state = dummy;
    ref.read(dummyDataActiveProvider.notifier).state = true;
    ref.read(prefsProvider).setBool('dummy_data_active', true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'dummy_added'))));
  }
}

class MyFinanceApp extends ConsumerWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingProvider);
    final theme = ref.watch(themeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primary,
          primary: theme.primary,
          secondary: theme.secondary,
          tertiary: theme.tertiary,
          brightness: Brightness.light,
        ),
        fontFamily: 'Satoshi',
        textTheme: Typography.material2021(platform: TargetPlatform.android)
            .black
            .apply(fontFamily: 'Satoshi', bodyColor: const Color(0xFF25212E), displayColor: const Color(0xFF25212E)),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF1EEF7),
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: theme.primary, width: 1.4)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1B27),
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: theme.primary,
          secondary: theme.secondary,
          tertiary: theme.tertiary,
          surface: const Color(0xFF121016),
          onSurface: Colors.white,
        ),
        fontFamily: 'Satoshi',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        iconTheme: const IconThemeData(color: Colors.white),
        textTheme: Typography.material2021(platform: TargetPlatform.android)
            .white
            .apply(fontFamily: 'Satoshi', bodyColor: Colors.white, displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF29253363),
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white, width: 1.2)),
        ),
      ),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark ? const Color(0xFF1E1B27) : Colors.white,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(0.9).clamp(0.85, 1.0),
              ),
            ),
            child: child!,
          ),
        );
      },
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
  final slideKeys = const [
    ('onboarding_title_1', 'onboarding_desc_1'),
    ('onboarding_title_2', 'onboarding_desc_2'),
    ('onboarding_title_3', 'onboarding_desc_3'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final last = page == slideKeys.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('MY FINANCE', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w900, letterSpacing: 2)),
              TextButton(onPressed: () => _finish(), child: Text(Strings.t(lang, 'skip'))),
            ]),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 330, width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? colors.primary.withOpacity(0.16) : colors.tertiary, borderRadius: BorderRadius.circular(40),
                  ),
                  child: Stack(children: [
                    Positioned(top: 42, left: 28, child: _orb(colors.primary.withOpacity(0.4), 54)),
                    Positioned(top: 88, right: 40, child: _orb(colors.primary.withOpacity(0.7), 90)),
                    Positioned(bottom: 44, left: 80, child: _orb(colors.primary, 120)),
                    Center(child: Icon(last ? SolarIconsBold.chart : page == 1 ? SolarIconsBold.billList : SolarIconsBold.wallet, size: 94, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 40),
                Text(Strings.t(lang, slideKeys[page].$1), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 36, height: 1.08, color: context.textPrimary)),
                const SizedBox(height: 16),
                Text(Strings.t(lang, slideKeys[page].$2), style: TextStyle(fontSize: 16, height: 1.5, color: context.textMuted)),
              ]),
            ),
            Row(children: [
              ...List.generate(3, (i) => AnimatedContainer(duration: const Duration(milliseconds: 220), margin: const EdgeInsets.only(right: 6), width: i == page ? 28 : 7, height: 7, decoration: BoxDecoration(color: i == page ? colors.primary : (isDark ? Colors.white24 : colors.tertiary), borderRadius: BorderRadius.circular(20)))),
              const Spacer(),
              FilledButton.icon(onPressed: () => last ? _finish() : setState(() => page++), icon: Icon(last ? Icons.check : SolarIconsOutline.arrowRight), label: Text(last ? Strings.t(lang, 'get_started') : Strings.t(lang, 'continue'))),
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
    final lang = ref.watch(langProvider);
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: List.generate(
            pages.length,
            (i) => AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              curve: tab == i ? Curves.easeOut : Curves.easeIn,
              opacity: tab == i ? 1 : 0,
              child: IgnorePointer(
                ignoring: tab != i,
                child: RepaintBoundary(child: pages[i]),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(context, 0, SolarIconsOutline.home, SolarIconsBold.home, Strings.t(lang, 'nav_home'), tab, ref),
            _navItem(context, 1, SolarIconsOutline.chart, SolarIconsBold.chart, Strings.t(lang, 'nav_statistic'), tab, ref),
            GestureDetector(
              onTap: () {},
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(SolarIconsOutline.scanner, color: Colors.black),
              ),
            ),
            _navItem(context, 2, SolarIconsOutline.billList, SolarIconsBold.billList, Strings.t(lang, 'nav_card'), tab, ref),
            _navItem(context, 3, SolarIconsOutline.user, SolarIconsBold.user, Strings.t(lang, 'nav_profile'), tab, ref, onLongPress: () => toggleDummyData(context, ref)),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int index, IconData iconOutline, IconData iconBold, String label, int currentTab, WidgetRef ref, {VoidCallback? onLongPress}) {
    final isSelected = currentTab == index;
    final color = isSelected ? context.textPrimary : context.iconMuted;
    return GestureDetector(
      onTap: () => ref.read(tabProvider.notifier).state = index,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  isSelected ? iconBold : iconOutline,
                  key: ValueKey<bool>(isSelected),
                  color: color,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(fontSize: 10, color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final cards = ref.watch(cardsProvider);
    final rawSelectedCard = ref.watch(selectedCardProvider);
    final isAllAccounts = rawSelectedCard == -1;
    final safeSelectedCard = cards.isEmpty ? 0 : (rawSelectedCard >= cards.length ? cards.length - 1 : (rawSelectedCard < 0 ? 0 : rawSelectedCard));
    final selectedCardBalance = cards.isEmpty
        ? 0.0
        : (isAllAccounts ? cards.fold<double>(0, (a, c) => a + c.initialBalance) : cards[safeSelectedCard].initialBalance);
    final items = isAllAccounts ? allItems : allItems.where((e) => e.cardIndex == safeSelectedCard).toList();
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final balance = selectedCardBalance + income - expense;
    final primary = Theme.of(context).colorScheme.primary;
    final accent = Theme.of(context).colorScheme.secondary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final isDark = context.isDark;

    final topInset = MediaQuery.paddingOf(context).top;
    return SafeArea(
      top: false,
      child: ListView(
        controller: _scrollController,
        primary: false,
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withOpacity(0.26) : Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(children: [
              Container(
                  padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 32),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(primary.withOpacity(isDark ? 0.22 : 0.14), context.cardColor).withOpacity(isDark ? 0.86 : 0.82),
                        Color.alphaBlend(primary.withOpacity(isDark ? 0.16 : 0.08), context.cardColor).withOpacity(isDark ? 0.68 : 0.58),
                      ],
                    ),
                  ),
                  child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const HamburgerMorphMenu(),
                    Text(Strings.t(lang, 'my_account'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textPrimary)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          LiquidGlass(
                            borderRadius: 999,
                            tint: isDark ? Colors.black : null,
                            intensity: isDark ? 1.6 : 1.0,
                            borderColor: isDark ? context.borderColor : null,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(SolarIconsOutline.bell, size: 20, color: context.textPrimary),
                            ),
                          ),
                          Positioned(
                            right: -2, top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                              child: const Text('2', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Center(child: CardSelectorButton()),
                const SizedBox(height: 24),
                Center(child: Text(Strings.t(lang, 'your_balance'), style: TextStyle(color: context.textMuted, fontSize: 13, fontWeight: FontWeight.w500))),
                const SizedBox(height: 8),
                Center(
                  child: RepaintBoundary(
                    child: NumberFlow(
                      value: balance,
                      locale: 'id_ID',
                      format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '),
                      spring: NumberFlowSpring.ios,
                      transformTiming: const TimingConfig(
                        duration: Duration(milliseconds: 450),
                        curve: Curves.easeInOut,
                      ),
                      opacityTiming: const TimingConfig(
                        duration: Duration(milliseconds: 450),
                        curve: Curves.easeOut,
                      ),
                      tabularNums: true,
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1.8, color: context.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: primary.withOpacity(isDark ? 0.18 : 0.08), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(SolarIconsBold.stars, size: 14, color: primary),
                        const SizedBox(width: 6),
                        Text('${Strings.t(lang, 'saved_last_month').replaceAll('{amount}', rupiah(0))} >', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _actionBtn(context, SolarIconsOutline.arrowRightUp, Strings.t(lang, 'send'), primaryStyle: true, onTap: () => showTransactionForm(context, ref, false)),
                    _actionBtn(context, SolarIconsOutline.arrowLeftDown, Strings.t(lang, 'request'), primaryStyle: false, blackGlassInDark: true, onTap: () => showTransactionForm(context, ref, true)),
                    _actionBtn(context, SolarIconsOutline.transferHorizontal, Strings.t(lang, 'exchange'), primaryStyle: false, blackGlassInDark: true, onTap: () => ref.read(tabProvider.notifier).state = 2),
                    const MoreMorphMenu(),
                  ],
                ),
              ],
            ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BottomRoundedBorderPainter(
                        color: isDark ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.25),
                        highlightColor: isDark ? Colors.black.withOpacity(0.42) : Colors.white.withOpacity(0.95),
                        radius: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Strings.t(lang, 'top_merchants'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                  ],
                ),
                const SizedBox(height: 16),
                Builder(builder: (context) {
                  final promos = [
                    (Strings.t(lang, 'discount_title'), Strings.t(lang, 'discount_subtitle'), SolarIconsBold.bag2),
                    (Strings.t(lang, 'cashback_title'), Strings.t(lang, 'cashback_subtitle'), SolarIconsBold.wallet),
                  ];
                  final cardWidth = MediaQuery.sizeOf(context).width * 0.78;
                  return SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: promos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final promo = promos[i];
                        final isAiCard = i == 0;
                        return Container(
                          width: cardWidth,
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: i == 0 ? 2 : 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color.alphaBlend(primary.withOpacity(isDark ? 0.38 : 0.22), context.cardColor),
                                context.cardColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(promo.$1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text(promo.$2, style: TextStyle(color: context.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (isAiCard)
                                const RepaintBoundary(
                                  child: SizedBox(
                                    width: 70,
                                    height: 70,
                                    child: VisibilityAwareLottie(asset: 'assets/lottie/ai.json'),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                                  child: Icon(promo.$3, color: primary, size: 24),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Strings.t(lang, 'transaction_history'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                    GestureDetector(
                      onTap: () => ref.read(tabProvider.notifier).state = 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(isDark ? 0.18 : 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(Strings.t(lang, 'view_all'), style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 15, color: primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(Strings.t(lang, 'today'), style: TextStyle(color: context.textFaint, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                ...items.take(4).toList().asMap().entries.map(
                      (e) => StaggeredReveal(
                        key: ValueKey(e.value.id),
                        index: e.key,
                        stagger: true,
                        child: TransactionTile(item: e.value),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, {required bool primaryStyle, required VoidCallback onTap, bool blackGlassInDark = false}) {
    final accent = Theme.of(context).colorScheme.secondary;
    final isDark = context.isDark;
    final useBlackGlass = blackGlassInDark && isDark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            width: 68,
            height: 42,
            child: LiquidGlass(
              borderRadius: 16,
              tint: useBlackGlass ? Colors.black : (primaryStyle ? accent : null),
              intensity: useBlackGlass ? 1.6 : (primaryStyle ? (isDark ? 2.3 : 1.8) : 1.0),
              borderColor: useBlackGlass ? context.borderColor : null,
              child: Center(
                child: Icon(icon, color: useBlackGlass ? Colors.white : (primaryStyle ? Colors.black : context.textPrimary), size: 22),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
        ],
      ),
    );
  }
}

class HamburgerMorphMenu extends ConsumerWidget {
  const HamburgerMorphMenu({super.key});

  static const double _itemHeight = 36.0;
  static const double _dividerHeight = 4.0;
  static const double _iconSize = 19.0;
  static TextStyle _titleStyle(BuildContext context) =>
      TextStyle(color: context.textPrimary.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final profile = ref.watch(userProfileProvider);
    final initial = profile.name.isNotEmpty ? profile.name.substring(0, 1).toUpperCase() : '?';

    return GlassMenu(
      menuWidth: 212,
      menuBorderRadius: 26,
      itemBorderRadius: 18,
      items: [
        GlassMenuItem(
          height: 52,
          iconSize: _iconSize,
          titleStyle: _titleStyle(context),
          subtitle: Strings.t(lang, 'view_profile'),
          subtitleStyle: TextStyle(color: context.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
          title: profile.name.isNotEmpty ? profile.name : Strings.t(lang, 'view_profile'),
          icon: Transform.translate(
            offset: const Offset(-8, 0),
            child: ProfileAvatar(
              photoPath: profile.photoPath,
              photoBytesBase64: profile.photoBytesBase64,
              photoVersion: profile.photoVersion,
              initial: initial,
              radius: 18,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              Icon(SolarIconsOutline.altArrowRight, size: 14, color: context.iconMuted),
            ],
          ),
          onTap: () => ref.read(tabProvider.notifier).state = 3,
        ),
        const GlassMenuDivider(height: _dividerHeight),
        GlassMenuItem(
          height: _itemHeight,
          iconSize: _iconSize,
          iconColor: Theme.of(context).colorScheme.primary,
          titleStyle: _titleStyle(context),
          title: isDark ? Strings.t(lang, 'light') : Strings.t(lang, 'dark'),
          icon: Transform.translate(offset: const Offset(-8, 0), child: Icon(isDark ? SolarIconsOutline.sun : SolarIconsOutline.moon)),
          onTap: () {
            final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
            ref.read(themeModeProvider.notifier).state = newMode;
            ref.read(prefsProvider).setString('app_theme_mode', newMode.name);
          },
        ),
        GlassMenuItem(
          height: _itemHeight,
          iconSize: _iconSize,
          iconColor: Theme.of(context).colorScheme.primary,
          titleStyle: _titleStyle(context),
          title: Strings.t(lang, 'appearance'),
          icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.palette)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionPage())),
        ),
        GlassMenuItem(
          height: _itemHeight,
          iconSize: _iconSize,
          iconColor: Theme.of(context).colorScheme.primary,
          titleStyle: _titleStyle(context),
          title: Strings.t(lang, 'language'),
          icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(Icons.language)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionPage())),
        ),
        GlassMenuItem(
          height: _itemHeight,
          iconSize: _iconSize,
          iconColor: Theme.of(context).colorScheme.primary,
          titleStyle: _titleStyle(context),
          title: Strings.t(lang, 'notifications'),
          icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.bell)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
        ),
      ],
      settings: LiquidGlassSettings(
        blur: 18,
        thickness: 30,
        glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.55) : const Color.fromRGBO(255, 255, 255, 0.12),
        whitenStrength: 0.0,
        lightIntensity: isDark ? 0.12 : 0.95,
        ambientStrength: isDark ? 0.08 : 0.55,
        saturation: isDark ? 1.6 : 1.9,
        refractiveIndex: isDark ? 0.18 : 1.85,
        chromaticAberration: isDark ? 0.0 : 2.2,
        fresnelStrength: isDark ? 0.0 : 1.0,
        glowIntensity: isDark ? 0.0 : 0.75,
      ),
      trigger: LiquidGlass(
        borderRadius: 999,
        tint: isDark ? Colors.black : null,
        intensity: isDark ? 1.6 : 1.0,
        borderColor: isDark ? context.borderColor : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(SolarIconsOutline.hamburgerMenu, size: 20, color: context.textPrimary),
        ),
      ),
    );
  }
}

class MoreMorphMenu extends ConsumerStatefulWidget {
  const MoreMorphMenu({super.key});

  static const double _itemHeight = 36.0;
  static const double _dividerHeight = 4.0;
  static const double _iconSize = 18.0;
  static TextStyle _titleStyle(BuildContext context) =>
      TextStyle(color: context.textPrimary.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w600);
  // 5 items + 2 dividers + 24 padding (12 top + 12 bottom) + 6 gaps of 2px each.
  static const double _estimatedMenuHeight = 5 * _itemHeight + 2 * _dividerHeight + 24 + 12;

  @override
  ConsumerState<MoreMorphMenu> createState() => _MoreMorphMenuState();
}

class _MoreMorphMenuState extends ConsumerState<MoreMorphMenu> {
  final GlobalKey _triggerKey = GlobalKey();
  GlassMenuAlignment _alignment = GlassMenuAlignment.bottomRight;

  // Measures the trigger's live position right before opening, so the
  // decision reacts to the current scroll offset instead of a stale value.
  // Prefers opening UPWARD; only falls back to downward when the space
  // above the trigger isn't enough to fit the menu.
  void _updateAlignmentThenToggle(VoidCallback toggleMenu) {
    final renderObject = _triggerKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached) {
      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      final screenSize = MediaQuery.sizeOf(context);
      final topInset = MediaQuery.paddingOf(context).top;
      final spaceAbove = position.dy - topInset;
      final isRightHalf = position.dx + size.width / 2 > screenSize.width / 2;
      final preferUp = spaceAbove >= MoreMorphMenu._estimatedMenuHeight + 16;
      final newAlignment = preferUp
          ? (isRightHalf ? GlassMenuAlignment.bottomRight : GlassMenuAlignment.bottomLeft)
          : (isRightHalf ? GlassMenuAlignment.topRight : GlassMenuAlignment.topLeft);
      setState(() => _alignment = newAlignment);
    }
    // Wait one frame so GlassMenu rebuilds with the fresh alignment
    // before the morph actually captures the trigger position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) toggleMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final lang = ref.watch(langProvider);

    return Column(
      children: [
        GlassMenu(
          menuAlignment: _alignment,
          menuWidth: 204,
          menuBorderRadius: 26,
          itemBorderRadius: 18,
          items: [
            GlassMenuItem(
              height: MoreMorphMenu._itemHeight,
              iconSize: MoreMorphMenu._iconSize,
              iconColor: Theme.of(context).colorScheme.primary,
              titleStyle: MoreMorphMenu._titleStyle(context),
              title: Strings.t(lang, 'account_wallet'),
              icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.wallet)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CardManagementPage())),
            ),
            GlassMenuItem(
              height: MoreMorphMenu._itemHeight,
              iconSize: MoreMorphMenu._iconSize,
              iconColor: Theme.of(context).colorScheme.primary,
              titleStyle: MoreMorphMenu._titleStyle(context),
              title: Strings.t(lang, 'receivables'),
              icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.usersGroupTwoRounded)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoanManagementPage())),
            ),
            const GlassMenuDivider(height: MoreMorphMenu._dividerHeight),
            GlassMenuItem(
              height: MoreMorphMenu._itemHeight,
              iconSize: MoreMorphMenu._iconSize,
              iconColor: Theme.of(context).colorScheme.primary,
              titleStyle: MoreMorphMenu._titleStyle(context),
              title: Strings.t(lang, 'appearance'),
              icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.palette)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionPage())),
            ),
            GlassMenuItem(
              height: MoreMorphMenu._itemHeight,
              iconSize: MoreMorphMenu._iconSize,
              iconColor: Theme.of(context).colorScheme.primary,
              titleStyle: MoreMorphMenu._titleStyle(context),
              title: Strings.t(lang, 'language'),
              icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(Icons.language)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionPage())),
            ),
            const GlassMenuDivider(height: MoreMorphMenu._dividerHeight),
            GlassMenuItem(
              height: MoreMorphMenu._itemHeight,
              iconSize: MoreMorphMenu._iconSize,
              iconColor: Theme.of(context).colorScheme.primary,
              titleStyle: MoreMorphMenu._titleStyle(context),
              title: Strings.t(lang, 'savings_target'),
              icon: Transform.translate(offset: const Offset(-8, 0), child: const Icon(SolarIconsOutline.safeSquare)),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'not_available').replaceAll('{name}', Strings.t(lang, 'savings_target'))))),
            ),
          ],
          settings: LiquidGlassSettings(
            blur: 18,
            thickness: 30,
            glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.55) : const Color.fromRGBO(255, 255, 255, 0.12),
            whitenStrength: 0.0,
            lightIntensity: isDark ? 0.12 : 0.95,
            ambientStrength: isDark ? 0.08 : 0.55,
            saturation: isDark ? 1.6 : 1.9,
            refractiveIndex: isDark ? 0.18 : 1.85,
            chromaticAberration: isDark ? 0.0 : 2.2,
            fresnelStrength: isDark ? 0.0 : 1.0,
            glowIntensity: isDark ? 0.0 : 0.75,
          ),
          triggerBuilder: (context, toggleMenu) => GestureDetector(
            onTap: () => _updateAlignmentThenToggle(toggleMenu),
            child: SizedBox(
              key: _triggerKey,
              width: 68,
              height: 42,
              child: LiquidGlass(
                borderRadius: 16,
                tint: isDark ? Colors.black : null,
                intensity: isDark ? 1.6 : 1.0,
                borderColor: isDark ? context.borderColor : null,
                child: Center(
                  child: Icon(SolarIconsOutline.menuDots, color: isDark ? Colors.white : context.textPrimary, size: 22),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(Strings.t(lang, 'more'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
      ],
    );
  }
}

class CardSelectorButton extends ConsumerStatefulWidget {
  const CardSelectorButton({super.key});

  @override
  ConsumerState<CardSelectorButton> createState() => _CardSelectorButtonState();
}

class _CardSelectorButtonState extends ConsumerState<CardSelectorButton> {
  final _menuController = GlassMenuController();
  final _cardsScrollController = ScrollController();

  static const _itemHeight = 36.0;
  static const _dividerHeight = 4.0;
  static const _itemGap = 2.0;
  static const _edgePadding = 12.0;
  static const _maxVisibleCards = 3;

  // Matches the GlassMenu's normal-speed morph-close profile (~375ms) so the
  // balance counter only starts animating once the popup has visually
  // shrunk away, instead of running underneath it.
  static const _selectionApplyDelay = Duration(milliseconds: 400);

  void _applySelection(int index) {
    Future.delayed(_selectionApplyDelay, () {
      if (!mounted) return;
      ref.read(selectedCardProvider.notifier).state = index;
    });
  }

  @override
  void dispose() {
    _cardsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final rawSelected = ref.watch(selectedCardProvider);
    final selected = rawSelected == -1 ? -1 : (rawSelected >= cards.length ? cards.length - 1 : (rawSelected < 0 ? 0 : rawSelected));
    final lang = ref.watch(langProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = context.isDark;

    final visibleCardCount = cards.length < _maxVisibleCards ? cards.length : _maxVisibleCards;
    final cardsAreaHeight = visibleCardCount == 0 ? 0.0 : visibleCardCount * _itemHeight + (visibleCardCount - 1) * _itemGap;
    final menuTotalHeight = _edgePadding * 2 +
        _itemHeight +
        _itemGap +
        _dividerHeight +
        _itemGap +
        cardsAreaHeight +
        _itemGap +
        _dividerHeight +
        _itemGap +
        _itemHeight;

    return GlassMenu(
      controller: _menuController,
      items: [
        GlassMenuItem(
          title: Strings.t(lang, 'all_accounts'),
          icon: const Icon(Icons.dashboard_outlined),
          iconColor: rawSelected == -1 ? primary : null,
          titleStyle: TextStyle(color: context.textPrimary.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w600),
          isSelected: rawSelected == -1,
          trailing: rawSelected == -1 ? Icon(Icons.check_rounded, color: primary, size: 18) : null,
          height: _itemHeight,
          onTap: () => _applySelection(-1),
        ),
        GlassMenuDivider(height: _dividerHeight),
        SizedBox(
          height: cardsAreaHeight,
          child: cards.isEmpty
              ? const SizedBox.shrink()
              : RawScrollbar(
                  controller: _cardsScrollController,
                  thumbVisibility: cards.length > _maxVisibleCards,
                  thumbColor: primary.withOpacity(context.isDark ? 0.5 : 0.35),
                  radius: const Radius.circular(8),
                  thickness: 3,
                  minThumbLength: 24,
                  child: ListView.separated(
                    controller: _cardsScrollController,
                    padding: const EdgeInsets.only(right: 6),
                    physics: const ClampingScrollPhysics(),
                    itemCount: cards.length,
                    separatorBuilder: (_, __) => const SizedBox(height: _itemGap),
                    itemBuilder: (context, i) {
                      final isCurrent = rawSelected == i;
                      return GlassMenuItem(
                        title: cards[i].name,
                        icon: const Icon(SolarIconsOutline.card),
                        iconColor: isCurrent ? primary : null,
                        titleStyle: TextStyle(color: context.textPrimary.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w600),
                        isSelected: isCurrent,
                        trailing: isCurrent ? Icon(Icons.check_rounded, color: primary, size: 18) : null,
                        height: _itemHeight,
                        onTap: () {
                          _menuController.close();
                          _applySelection(i);
                        },
                      );
                    },
                  ),
                ),
        ),
        GlassMenuDivider(height: _dividerHeight),
        GlassMenuItem(
          title: Strings.t(lang, 'add_card'),
          icon: const Icon(SolarIconsOutline.addCircle),
          iconColor: primary,
          titleStyle: TextStyle(color: primary, fontSize: 13.5, fontWeight: FontWeight.w600),
          height: _itemHeight,
          onTap: () => Future.microtask(() => showCardForm(context: context, ref: ref)),
        ),
      ],
      settings: LiquidGlassSettings(
        blur: 18,
        thickness: 30,
        glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.55) : const Color.fromRGBO(255, 255, 255, 0.12),
        whitenStrength: 0.0,
        lightIntensity: isDark ? 0.12 : 0.95,
        ambientStrength: isDark ? 0.08 : 0.55,
        saturation: isDark ? 1.6 : 1.9,
        refractiveIndex: isDark ? 0.18 : 1.85,
        chromaticAberration: isDark ? 0.0 : 2.2,
        fresnelStrength: isDark ? 0.0 : 1.0,
        glowIntensity: isDark ? 0.0 : 0.75,
      ),
      menuAlignment: GlassMenuAlignment.topCenter,
      menuWidth: 198,
      menuHeight: menuTotalHeight,
      trigger: _ClosedCardChip(
        cardLabel: selected == -1 ? Strings.t(lang, 'all_accounts') : cards[selected].number,
        showArrow: true,
      ),
    );
  }
}

class _ClosedCardChip extends StatelessWidget {
  final String cardLabel;
  final bool showArrow;
  const _ClosedCardChip({required this.cardLabel, this.showArrow = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: showArrow ? context.cardColor : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: showArrow ? Border.all(color: context.borderColor) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22, height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
            child: const Icon(SolarIconsBold.wallet, size: 12, color: Colors.black87),
          ),
          const SizedBox(width: 8),
          Text(cardLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
          if (showArrow) ...[
            const SizedBox(width: 4),
            Icon(SolarIconsOutline.altArrowDown, size: 16, color: context.iconMuted),
          ],
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
class _TransactionsPageState extends ConsumerState<TransactionsPage> with TickerProviderStateMixin {
  String query = '';
  String filter = 'all';
  int? cardFilter;
  double minAmountFilter = 0;
  bool _sliderDragging = false;
  bool _minAmountExpanded = false;
  int _displayCount = _pageSize;
  final ScrollController _scrollController = ScrollController();
  static const filterKeys = ['all', 'income', 'expense'];
  static const _pageSize = 10;
  static const _maxAmountFilter = 5000000.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      setState(() => _displayCount += _pageSize);
    }
  }

  void _resetPaging() {
    _displayCount = _pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final cards = ref.watch(cardsProvider);
    final items = all.where((e) =>
        (filter == 'all' || (filter == 'income' ? e.income : !e.income)) &&
        (cardFilter == null || e.cardIndex == cardFilter) &&
        (!_minAmountExpanded || e.amount >= minAmountFilter) &&
        e.title.toLowerCase().contains(query.toLowerCase())).toList();
    final visibleCount = _displayCount < items.length ? _displayCount : items.length;
    final hasMore = visibleCount < items.length;
    return SafeArea(top: false, child: ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24),
      cacheExtent: 600,
      itemCount: visibleCount + 1 + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Strings.t(lang, 'transactions_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
              Text(Strings.t(lang, 'transactions_subtitle'), style: TextStyle(color: context.textMuted)),
              const SizedBox(height: 22),
              TextField(onChanged: (v) => setState(() { query = v; _resetPaging(); }), decoration: InputDecoration(hintText: Strings.t(lang, 'search_transactions'), prefixIcon: const Icon(Icons.search))),
              const SizedBox(height: 14),
              GlassSegmentedControl(
                segments: filterKeys
                    .map((k) => GlassSegment(label: Strings.t(lang, 'filter_$k')))
                    .toList(),
                selectedIndex: filterKeys.indexOf(filter),
                indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(context.isDark ? 0.25 : 0.15),
                onSegmentSelected: (index) {
                  setState(() {
                    filter = filterKeys[index];
                    _resetPaging();
                  });
                },
                quality: GlassQuality.premium,
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(Strings.t(lang, 'all_accounts')),
                        selected: cardFilter == null,
                        onSelected: (_) => setState(() { cardFilter = null; _resetPaging(); }),
                      ),
                    ),
                    ...cards.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value.name),
                              selected: cardFilter == e.key,
                              onSelected: (_) => setState(() { cardFilter = e.key; _resetPaging(); }),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _minAmountExpanded = !_minAmountExpanded),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Nominal minimal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textMuted)),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _minAmountExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(SolarIconsOutline.altArrowDown, size: 14, color: context.iconMuted),
                        ),
                      ],
                    ),
                    if (_minAmountExpanded)
                      Text(rupiah(minAmountFilter), style: TextStyle(fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _minAmountExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const thumbRadius = 15.0;
                      const thumbWidth = thumbRadius * 2.6;
                      const thumbHeight = thumbRadius * 1.6;
                      const widgetHeight = thumbRadius * 2 + 16;
                      final trackWidth = constraints.maxWidth - thumbRadius * 2;
                      final normalized = ((minAmountFilter - 0) / (_maxAmountFilter - 0)).clamp(0.0, 1.0);
                      final thumbCenterX = thumbRadius + trackWidth * normalized;
                      const topPosition = (widgetHeight - thumbHeight) / 2;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: thumbCenterX - thumbRadius,
                            top: topPosition,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _sliderDragging ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: Container(
                                  width: thumbWidth,
                                  height: thumbHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(thumbHeight / 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(context.isDark ? 0.28 : 0.16),
                                        blurRadius: 7,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          GlassSlider(
                            value: minAmountFilter,
                            min: 0,
                            max: _maxAmountFilter,
                            divisions: 20,
                            activeColor: Theme.of(context).colorScheme.primary,
                            quality: GlassQuality.premium,
                            onChangeStart: (_) => setState(() => _sliderDragging = true),
                            onChangeEnd: (_) => setState(() => _sliderDragging = false),
                            onChanged: (v) => setState(() {
                              minAmountFilter = v;
                              _resetPaging();
                            }),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        }
        if (hasMore && index == visibleCount + 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
          );
        }
        final e = items[index - 1];
        return StaggeredReveal(
          animate: true,
          index: index - 1,
          child: TransactionTile(item: e),
        );
      },
    ));
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.watch(transactionsProvider);
    final lang = ref.watch(langProvider);
    final cards = ref.watch(cardsProvider);
    final rawSelectedCard = ref.watch(selectedCardProvider);
    final isAllAccounts = rawSelectedCard == -1;
    final safeSelectedCard = cards.isEmpty ? 0 : (rawSelectedCard >= cards.length ? cards.length - 1 : (rawSelectedCard < 0 ? 0 : rawSelectedCard));
    final items = isAllAccounts ? allItems : allItems.where((e) => e.cardIndex == safeSelectedCard).toList();
    final income = items.where((e) => e.income).fold<double>(0, (a, b) => a + b.amount);
    final expense = items.where((e) => !e.income).fold<double>(0, (a, b) => a + b.amount);
    final groups = <String, double>{};
    for (final item in items.where((e) => !e.income)) groups[item.category] = (groups[item.category] ?? 0) + item.amount;
    final safeGroups = Map<String, double>.fromEntries(groups.entries.where((e) => e.value > 0));
    return SafeArea(top: false, child: ListView(padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24), children: [
      Text(Strings.t(lang, 'reports_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
      Text(AppFormatters.monthYear(lang).format(DateTime(2026, 8, 24)), style: TextStyle(color: context.textMuted)),
      const SizedBox(height: 6),
      Text(isAllAccounts ? Strings.t(lang, 'all_accounts') : (cards.isEmpty ? '' : cards[safeSelectedCard].name), style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 22),
      RepaintBoundary(child: SummaryCard(income: income, expense: expense)),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'cash_flow')),
      const SizedBox(height: 12),
      Container(height: 190, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)), child: RepaintBoundary(child: CustomPaint(painter: SimpleChartPainter(primary: Theme.of(context).colorScheme.primary, gridColor: context.isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEDEAF2))))),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'expense_by_category')),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)), child: safeGroups.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(Strings.t(lang, 'no_expenses_yet'), style: TextStyle(color: context.textMuted, fontSize: 13)))
          : Builder(builder: (context) {
              final entries = safeGroups.entries.toList();
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];
                  return StaggeredReveal(index: index, child: ReportRow(label: e.key, amount: e.value, total: expense));
                },
              );
            })),
    ]));
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final profile = ref.watch(userProfileProvider);
    final initial = profile.name.isNotEmpty ? profile.name.substring(0, 1).toUpperCase() : '?';
    return SafeArea(top: false, child: ListView(padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 22, 20, 24), children: [
      Text(Strings.t(lang, 'profile_title'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 32, color: context.textPrimary)),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)),
        child: Row(children: [
          GestureDetector(
            onTap: () => showProfilePhotoOptions(context, ref),
            child: Stack(clipBehavior: Clip.none, children: [
              ProfileAvatar(
                photoPath: profile.photoPath,
                photoBytesBase64: profile.photoBytesBase64,
                photoVersion: profile.photoVersion,
                initial: initial,
                radius: 31,
              ),
              Positioned(
                right: -2, bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.cardColor, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.black),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(profile.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(context.isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded, size: 11, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        Strings.t(lang, 'premium_member'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.0, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => showEditNameDialog(context, ref),
                  child: Icon(Icons.edit_outlined, size: 16, color: context.iconMuted),
                ),
              ]),
              const SizedBox(height: 4),
              Text(Strings.t(lang, 'manage_account'), style: TextStyle(color: context.textMuted)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 26),
      SectionTitle(Strings.t(lang, 'section_finance')),
      const SizedBox(height: 10),
      SettingList(items: const [
        ('savings_target', SolarIconsOutline.safeSquare),
        ('category', SolarIconsOutline.widget),
        ('account_wallet', SolarIconsOutline.wallet),
        ('receivables', SolarIconsOutline.usersGroupTwoRounded),
      ]),
      const SizedBox(height: 24),
      SectionTitle(Strings.t(lang, 'section_app')),
      const SizedBox(height: 10),
      SettingList(items: const [
        ('appearance', SolarIconsOutline.palette),
        ('language', Icons.language),
        ('notifications', SolarIconsOutline.bell),
        ('backup_data', SolarIconsOutline.cloudUpload),
      ]),
    ]));
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.textPrimary));
}

class TransactionTile extends ConsumerWidget {
  final FinanceTransaction item;
  const TransactionTile({super.key, required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final cards = ref.watch(cardsProvider);
    final cardName = (item.cardIndex >= 0 && item.cardIndex < cards.length) ? cards[item.cardIndex].name : '';
    return GestureDetector(
      onTap: () {
        if (item.category == 'Pinjaman Diberikan') {
          showTransactionLoanNotice(context, ref, item);
        } else {
          showTransactionActions(context, ref, item);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: context.isDark ? primary.withOpacity(0.18) : Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  item.title.substring(0, 1).toUpperCase(),
                  style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.textPrimary)),
                  const SizedBox(height: 4),
                  Text(cardName.isEmpty ? AppFormatters.hourMinute.format(item.date) : '$cardName · ${AppFormatters.hourMinute.format(item.date)}', style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                NumberFlow(
                  value: item.amount,
                  locale: 'id_ID',
                  format: NumberFlowFormat.currency(currencyCode: 'IDR', symbol: item.income ? '+Rp ' : '-Rp '),
                  style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -0.2, color: context.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(Strings.t(lang, item.income ? 'receive' : 'transfer'), style: TextStyle(color: context.textFaint, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryCard extends ConsumerWidget {
  final double income, expense;
  const SummaryCard({super.key, required this.income, required this.expense});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _summary(context, Strings.t(lang, 'income'), NumberFlow(value: income, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: const TextStyle(fontFamily: 'Satoshi', color: Color(0xFF24A148), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -1.2))),
      Container(width: 1, height: 44, color: context.borderColor),
      _summary(context, Strings.t(lang, 'expense'), NumberFlow(value: expense, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: const TextStyle(fontFamily: 'Satoshi', color: Color(0xFFE05270), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -1.2))),
      Container(width: 1, height: 44, color: context.borderColor),
      _summary(context, Strings.t(lang, 'savings'), Row(mainAxisSize: MainAxisSize.min, children: [NumberFlow(value: income == 0 ? 0 : ((income - expense) / income * 100).round(), style: TextStyle(fontFamily: 'Satoshi', color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -1.2)), Text('%', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -1.2))])),
    ]));
  }
  Widget _summary(BuildContext context, String title, Widget valueWidget) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(title, style: TextStyle(color: context.textMuted, fontSize: 11)), const SizedBox(height: 7), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center, child: valueWidget)]));
}

class ReportRow extends StatelessWidget {
  final String label; final double amount, total;
  const ReportRow({super.key, required this.label, required this.amount, required this.total});
  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary)), Row(mainAxisSize: MainAxisSize.min, children: [NumberFlow(value: amount, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textMuted, fontSize: 12, letterSpacing: -1.0)), Text(' · ${(ratio * 100).round()}%', style: TextStyle(color: context.textMuted, fontSize: 12))])]), const SizedBox(height: 8), LinearProgressIndicator(value: ratio, minHeight: 7, borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.primary, backgroundColor: context.isDark ? Theme.of(context).colorScheme.primary.withOpacity(0.16) : Theme.of(context).colorScheme.tertiary)]));
  }
}

class SettingList extends ConsumerWidget {
  final List<(String, IconData)> items;
  const SettingList({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: items
            .map<Widget>(
              (item) {
                final label = Strings.t(lang, item.$1);
                return ListTile(
                  onTap: () {
                    if (item.$1 == 'appearance') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionPage()));
                    } else if (item.$1 == 'language') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionPage()));
                    } else if (item.$1 == 'account_wallet') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CardManagementPage()));
                    } else if (item.$1 == 'receivables') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoanManagementPage()));
                    } else if (item.$1 == 'category') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CategorySettingsPage()));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'not_available').replaceAll('{name}', label))));
                    }
                  },
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.$2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(label, style: TextStyle(color: context.textPrimary)),
                  trailing: Icon(SolarIconsOutline.altArrowRight, size: 20, color: context.iconMuted),
                );
              },
            )
            .toList(),
      ),
    );
  }
}

class ThemeSelectionPage extends ConsumerWidget {
  const ThemeSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeProvider);
    final currentMode = ref.watch(themeModeProvider);
    final lang = ref.watch(langProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
    final cardBg = isDark ? const Color(0xFF1E1B27) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: isDark ? Colors.white : Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(Strings.t(lang, 'appearance'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Text(Strings.t(lang, 'screen_mode'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        _modeBtn(context, ref, Strings.t(lang, 'light'), SolarIconsOutline.sun, ThemeMode.light, currentMode),
                        _modeBtn(context, ref, Strings.t(lang, 'dark'), SolarIconsOutline.moon, ThemeMode.dark, currentMode),
                        _modeBtn(context, ref, Strings.t(lang, 'system'), SolarIconsOutline.monitor, ThemeMode.system, currentMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(Strings.t(lang, 'theme_color'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Column(
                      children: appPalettes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final palette = entry.value;
                        final isSelected = currentTheme.name == palette.name;
                        
                        return Column(
                          children: [
                            ListTile(
                              onTap: () {
                                ref.read(themeProvider.notifier).state = palette;
                                ref.read(prefsProvider).setString('app_theme_palette', palette.name);
                              },
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12, width: 0.5),
                                  gradient: SweepGradient(
                                    colors: [
                                      palette.primary, palette.primary,
                                      palette.secondary, palette.secondary,
                                      palette.tertiary, palette.tertiary
                                    ],
                                    stops: const [0.0, 0.33, 0.33, 0.66, 0.66, 1.0],
                                  ),
                                ),
                              ),
                              title: Text(palette.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              trailing: isSelected 
                                  ? Icon(SolarIconsBold.checkCircle, color: palette.primary, size: 28)
                                  : Icon(SolarIconsOutline.roundAltArrowRight, color: context.iconMuted, size: 24),
                            ),
                            if (index != appPalettes.length - 1)
                              Divider(height: 1, indent: 80, endIndent: 20, color: isDark ? Colors.white12 : Colors.grey.shade100),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(BuildContext context, WidgetRef ref, String title, IconData icon, ThemeMode mode, ThemeMode currentMode) {
    final isSelected = currentMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(themeModeProvider.notifier).state = mode;
          ref.read(prefsProvider).setString('app_theme_mode', mode.name);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? Colors.white12 : primary.withOpacity(0.08)) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? primary : context.iconMuted, size: 24),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? primary : context.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageSelectionPage extends ConsumerWidget {
  const LanguageSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final cardBg = context.cardColor;
    final primary = Theme.of(context).colorScheme.primary;
    final options = [
      (AppLang.en, 'English', 'EN'),
      (AppLang.id, 'Bahasa Indonesia', 'ID'),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
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
                  Text(Strings.t(lang, 'language'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Container(
                    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)),
                    child: Column(
                      children: options.asMap().entries.map((entry) {
                        final i = entry.key;
                        final opt = entry.value;
                        final selected = lang == opt.$1;
                        return Column(children: [
                          ListTile(
                            onTap: () {
                              ref.read(langProvider.notifier).state = opt.$1;
                              ref.read(prefsProvider).setString('app_lang', opt.$1 == AppLang.id ? 'id' : 'en');
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            leading: CircleAvatar(radius: 20, backgroundColor: primary.withOpacity(isDark ? 0.22 : 0.1), child: Text(opt.$3, style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 12))),
                            title: Text(opt.$2, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: context.textPrimary)),
                            trailing: selected
                                ? Icon(SolarIconsBold.checkCircle, color: primary, size: 26)
                                : Icon(SolarIconsOutline.roundAltArrowRight, color: context.iconMuted, size: 22),
                          ),
                          if (i != options.length - 1) Divider(height: 1, indent: 76, endIndent: 20, color: context.borderColor),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategorySettingsPage extends ConsumerWidget {
  const CategorySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final enabled = ref.watch(categoryFeatureEnabledProvider);
    final customCategories = ref.watch(customCategoriesProvider);
    final isDark = context.isDark;
    final primary = Theme.of(context).colorScheme.primary;

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
                    child: Padding(padding: const EdgeInsets.all(10), child: Icon(SolarIconsOutline.arrowLeft, size: 20, color: context.textPrimary)),
                  ),
                ),
                const SizedBox(width: 16),
                Text(Strings.t(lang, 'category'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Strings.t(lang, 'enable_category_feature'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: context.textPrimary)),
                              const SizedBox(height: 4),
                              Text(Strings.t(lang, 'enable_category_feature_desc'), style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.3)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GlassSwitch(
                          value: enabled,
                          activeColor: primary,
                          onChanged: (v) {
                            ref.read(categoryFeatureEnabledProvider.notifier).state = v;
                            ref.read(prefsProvider).setBool('category_feature_enabled', v);
                          },
                          width: 56,
                          height: 28,
                          quality: GlassQuality.premium,
                          useOwnLayer: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(Strings.t(lang, 'categories_list'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textFaint, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                    child: Column(children: [
                      ...allBuiltinCategoryKeys.asMap().entries.map((e) => Column(children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                              leading: Icon(SolarIconsOutline.widget, size: 18, color: primary),
                              title: Text(Strings.t(lang, e.value), style: TextStyle(color: context.textPrimary)),
                              trailing: Text(
                                Strings.t(lang, incomeCategoryKeys.contains(e.value) ? 'income' : 'expense'),
                                style: TextStyle(fontSize: 10, color: context.textFaint, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (e.key != allBuiltinCategoryKeys.length - 1 || customCategories.isNotEmpty)
                              Divider(height: 1, indent: 56, endIndent: 20, color: context.borderColor),
                          ])),
                      ...customCategories.asMap().entries.map((e) => Column(children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                              leading: Icon(SolarIconsOutline.widget, size: 18, color: primary),
                              title: Text(e.value, style: TextStyle(color: context.textPrimary)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                onPressed: () => ref.read(customCategoriesProvider.notifier).remove(e.value),
                              ),
                            ),
                            if (e.key != customCategories.length - 1) Divider(height: 1, indent: 56, endIndent: 20, color: context.borderColor),
                          ])),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final newCat = await promptNewCategoryDialog(context, lang);
                        if (newCat != null && newCat.trim().isNotEmpty) {
                          ref.read(customCategoriesProvider.notifier).add(newCat.trim());
                        }
                      },
                      icon: Icon(SolarIconsOutline.addCircle, size: 18, color: primary),
                      label: Text(Strings.t(lang, 'add_category'), style: TextStyle(color: primary)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final isDark = context.isDark;
    final bg = isDark ? const Color(0xFF121016) : const Color(0xFFF8F7FB);
    final cardBg = isDark ? const Color(0xFF1E1B27) : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final notifications = [
      (SolarIconsBold.wallet, 'Pemasukan diterima', 'Gaji bulanan sebesar Rp 0 telah masuk', '08:30'),
      (SolarIconsBold.bag2, 'Diskon spesial', 'Diskon hingga 80% untuk musim perayaan', 'Kemarin'),
      (SolarIconsBold.stars, 'Target tabungan', 'Kamu berhasil menghemat Rp 0 bulan lalu', '2 hari lalu'),
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
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
                  Text(Strings.t(lang, 'notifications'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: notifications.isEmpty
                  ? Center(child: Text(Strings.t(lang, 'not_available').replaceAll('{name}', Strings.t(lang, 'notifications')), style: TextStyle(color: context.textMuted)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      cacheExtent: 600,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = notifications[i];
                        return StaggeredReveal(
                          index: i,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                                child: Icon(item.$1, color: primary, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.$2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text(item.$3, style: TextStyle(color: context.textMuted, fontSize: 12, height: 1.4)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(item.$4, style: TextStyle(color: context.textFaint, fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimpleChartPainter extends CustomPainter {
  final Color primary;
  final Color gridColor;
  SimpleChartPainter({required this.primary, required this.gridColor});
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = gridColor..strokeWidth = 1;
    for (var i = 1; i < 5; i++) canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5), grid);
    final line = Paint()..color = primary..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height * .72)..cubicTo(size.width * .16, size.height * .50, size.width * .2, size.height * .62, size.width * .35, size.height * .48)..cubicTo(size.width * .5, size.height * .32, size.width * .62, size.height * .6, size.width * .76, size.height * .28)..cubicTo(size.width * .84, size.height * .18, size.width * .92, size.height * .35, size.width, size.height * .15);
    canvas.drawPath(path, line);
  }
  @override
  bool shouldRepaint(covariant SimpleChartPainter oldDelegate) => oldDelegate.primary != primary || oldDelegate.gridColor != gridColor;
}

class BottomRoundedBorderPainter extends CustomPainter {
  final Color color;
  final Color highlightColor;
  final double radius;
  final double strokeWidth;
  const BottomRoundedBorderPainter({required this.color, required this.highlightColor, required this.radius, this.strokeWidth = 1.2});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height - radius)
      ..arcToPoint(Offset(radius, size.height), radius: Radius.circular(radius), clockwise: false)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(Offset(size.width, size.height - radius), radius: Radius.circular(radius), clockwise: false);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [color, highlightColor, color],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, size.height - radius, size.width, radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BottomRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

Future<void> showTransactionForm(BuildContext context, WidgetRef ref, bool income, {FinanceTransaction? existing}) async {
  final isEdit = existing != null;
  final effectiveIncome = isEdit ? existing!.income : income;
  final amount = TextEditingController(text: isEdit ? AppFormatters.thousands.format(existing!.amount).replaceAll(',', '.') : '');
  final title = TextEditingController(text: existing?.title ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  final amountShakeKey = GlobalKey<ShakeFieldState>();
  final titleShakeKey = GlobalKey<ShakeFieldState>();
  final interestAmountCtrl = TextEditingController();
  final principalAmountCtrl = TextEditingController();
  final interestAmountShakeKey = GlobalKey<ShakeFieldState>();
  final principalAmountShakeKey = GlobalKey<ShakeFieldState>();
  final lang = ref.read(langProvider);
  final catKeys = effectiveIncome
      ? ['cat_income', 'cat_freelance', 'cat_bonus']
      : ['cat_food', 'cat_shopping', 'cat_transport', 'cat_bills', 'cat_other'];
  final catEnLabels = catKeys.map((k) => Strings.t(AppLang.en, k)).toList();
  String category = (existing != null && catEnLabels.contains(existing.category)) ? existing.category : catEnLabels.first;
  final categoryFeatureEnabled = ref.read(categoryFeatureEnabledProvider);
  var categoryOptions = [...catEnLabels, ...ref.read(customCategoriesProvider)];
  if (!categoryOptions.contains(category)) categoryOptions = [...categoryOptions, category];
  String? amountError;
  String? titleError;
  String? interestAmountError;
  String? principalAmountError;
  DateTime selectedDate = existing?.date ?? DateTime.now();
  final cards = ref.read(cardsProvider);
  final rawSelectedCard = ref.read(selectedCardProvider);
  int cardIndex = existing?.cardIndex ?? (rawSelectedCard >= 0 && rawSelectedCard < cards.length ? rawSelectedCard : 0);
  if (cardIndex < 0 || cardIndex >= cards.length) cardIndex = 0;
  final loans = ref.read(loansProvider);
  String? selectedLoanId;
  bool payInterestSelected = true;
  bool payPrincipalSelected = false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) {
      final isPiutangFlow = !isEdit && effectiveIncome && cardIndex >= 0 && cardIndex < cards.length && cards[cardIndex].type == CardType.piutang;
      final payableLoans = loans.where((l) => l.status != LoanStatus.paid).toList();
      return Padding(
    padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Strings.t(lang, isEdit ? (effectiveIncome ? 'edit_income' : 'edit_expense') : (effectiveIncome ? 'add_income' : 'add_expense')), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 28, color: context.textPrimary)),
      const SizedBox(height: 6),
      Text(Strings.t(lang, isEdit ? (effectiveIncome ? 'edit_income_subtitle' : 'edit_expense_subtitle') : (effectiveIncome ? 'add_income_subtitle' : 'add_expense_subtitle')), style: TextStyle(fontSize: 13, color: context.textMuted)),
      const SizedBox(height: 18),
      if (!isPiutangFlow) ...[
        ShakeField(
          key: amountShakeKey,
          child: TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()], decoration: InputDecoration(labelText: Strings.t(lang, 'amount'), prefixText: 'Rp ', errorText: amountError)),
        ),
        const SizedBox(height: 12),
        ShakeField(
          key: titleShakeKey,
          child: TextField(controller: title, decoration: InputDecoration(labelText: Strings.t(lang, 'transaction_title_field'), errorText: titleError)),
        ),
        const SizedBox(height: 12),
        if (categoryFeatureEnabled)
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: category,
                decoration: InputDecoration(labelText: Strings.t(lang, 'category')),
                items: categoryOptions.map((c) {
                  final key = builtinCategoryKeyFor(c);
                  final displayLabel = key != null ? Strings.t(lang, key) : c;
                  return DropdownMenuItem(value: c, child: Text(displayLabel, overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (v) => setModalState(() => category = v!),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                final newCat = await promptNewCategoryDialog(context, lang);
                if (newCat != null && newCat.trim().isNotEmpty) {
                  final trimmed = newCat.trim();
                  ref.read(customCategoriesProvider.notifier).add(trimmed);
                  setModalState(() {
                    if (!categoryOptions.contains(trimmed)) categoryOptions = [...categoryOptions, trimmed];
                    category = trimmed;
                  });
                }
              },
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(context.isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(SolarIconsOutline.addCircle, color: Theme.of(context).colorScheme.primary, size: 20),
              ),
            ),
          ]),
        if (categoryFeatureEnabled) const SizedBox(height: 12),
      ],
      DropdownButtonFormField<int>(
        value: cardIndex,
        decoration: InputDecoration(labelText: Strings.t(lang, 'use_card')),
        items: cards.asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.name))).toList(),
        onChanged: (v) => setModalState(() {
          cardIndex = v!;
          selectedLoanId = null;
        }),
      ),
      if (isPiutangFlow) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: selectedLoanId,
          decoration: InputDecoration(labelText: Strings.t(lang, 'borrower_name')),
          items: payableLoans.map((l) => DropdownMenuItem(value: l.id, child: Text(l.borrowerName))).toList(),
          onChanged: (v) => setModalState(() => selectedLoanId = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilterChip(
              label: Text(Strings.t(lang, 'interest_paid'), style: const TextStyle(fontSize: 11)),
              selected: payInterestSelected,
              onSelected: (v) => setModalState(() => payInterestSelected = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilterChip(
              label: Text(Strings.t(lang, 'principal_paid'), style: const TextStyle(fontSize: 11)),
              selected: payPrincipalSelected,
              onSelected: (v) => setModalState(() => payPrincipalSelected = v),
            ),
          ),
        ]),
        if (payInterestSelected) ...[
          const SizedBox(height: 12),
          ShakeField(
            key: interestAmountShakeKey,
            child: TextField(controller: interestAmountCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()], decoration: InputDecoration(labelText: Strings.t(lang, 'interest_paid'), prefixText: 'Rp ', errorText: interestAmountError)),
          ),
        ],
        if (payPrincipalSelected) ...[
          const SizedBox(height: 12),
          ShakeField(
            key: principalAmountShakeKey,
            child: TextField(controller: principalAmountCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()], decoration: InputDecoration(labelText: Strings.t(lang, 'principal_paid'), prefixText: 'Rp ', errorText: principalAmountError)),
          ),
        ],
      ],
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () async {
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (pickedDate == null || !context.mounted) return;
          final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
          setModalState(() {
            selectedDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime?.hour ?? selectedDate.hour, pickedTime?.minute ?? selectedDate.minute);
          });
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: Strings.t(lang, 'date')),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: context.iconMuted),
            const SizedBox(width: 10),
            Text(AppFormatters.dateTimeMinute(lang).format(selectedDate), style: TextStyle(fontSize: 14, color: context.textPrimary, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(controller: note, decoration: InputDecoration(labelText: Strings.t(lang, 'note_optional'))),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
        final value = double.tryParse(amount.text.replaceAll('.', '')) ?? 0;
        if (isPiutangFlow) {
          final interestValue = double.tryParse(interestAmountCtrl.text.replaceAll('.', '')) ?? 0;
          final principalValue = double.tryParse(principalAmountCtrl.text.replaceAll('.', '')) ?? 0;
          final noTypeSelected = !payInterestSelected && !payPrincipalSelected;
          final hasInterestError = payInterestSelected && interestValue <= 0;
          final hasPrincipalError = payPrincipalSelected && principalValue <= 0;
          if (noTypeSelected || hasInterestError || hasPrincipalError || selectedLoanId == null) {
            setModalState(() {
              interestAmountError = hasInterestError ? Strings.t(lang, 'field_required') : null;
              principalAmountError = hasPrincipalError ? Strings.t(lang, 'field_required') : null;
            });
            if (hasInterestError) interestAmountShakeKey.currentState?.shake();
            if (hasPrincipalError) principalAmountShakeKey.currentState?.shake();
            if (selectedLoanId == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'select_borrower_first'))));
            } else if (noTypeSelected) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.t(lang, 'field_required'))));
            }
            Future.delayed(const Duration(milliseconds: 3000), () {
              if (context.mounted) setModalState(() { interestAmountError = null; principalAmountError = null; });
            });
            return;
          }
          if (payInterestSelected) {
            ref.read(loansProvider.notifier).recordPayment(selectedLoanId!, isInterest: true, amount: interestValue, date: selectedDate, note: note.text.trim());
          }
          if (payPrincipalSelected) {
            ref.read(loansProvider.notifier).recordPayment(selectedLoanId!, isInterest: false, amount: principalValue, date: selectedDate, note: note.text.trim());
          }
          Navigator.pop(sheetContext);
          return;
        }
        final hasAmountError = value <= 0;
        final hasTitleError = title.text.trim().isEmpty;
        if (hasAmountError || hasTitleError) {
          setModalState(() {
            amountError = hasAmountError ? Strings.t(lang, 'field_required') : null;
            titleError = hasTitleError ? Strings.t(lang, 'field_required') : null;
          });
          if (hasAmountError) amountShakeKey.currentState?.shake();
          if (hasTitleError) titleShakeKey.currentState?.shake();
          Future.delayed(const Duration(milliseconds: 3000), () {
            if (context.mounted) {
              setModalState(() {
                amountError = null;
                titleError = null;
              });
            }
          });
          return;
        }
        if (isEdit) {
          final updatedTx = FinanceTransaction(id: existing!.id, title: title.text.trim(), category: category, note: note.text.trim(), amount: value, income: effectiveIncome, date: selectedDate, cardIndex: cardIndex, loanId: existing.loanId);
          ref.read(transactionsProvider.notifier).update(existing, updatedTx);
          if (existing.loanId != null) {
            ref.read(loansProvider.notifier).syncFromTransactionEdit(existing, updatedTx);
          }
        } else {
          ref.read(transactionsProvider.notifier).add(title: title.text.trim(), amount: value, income: effectiveIncome, category: category, note: note.text.trim(), date: selectedDate, cardIndex: cardIndex);
        }
        Navigator.pop(sheetContext);
      }, child: Text(Strings.t(lang, isEdit ? 'save_changes' : 'save_transaction')))),
    ]),
      );
    }),
  );
}

void showTransactionActions(BuildContext context, WidgetRef ref, FinanceTransaction item) {
  final lang = ref.read(langProvider);
  final primary = Theme.of(context).colorScheme.primary;
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: context.isDark ? primary.withOpacity(0.18) : Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle),
              child: Center(child: Text(item.title.substring(0, 1).toUpperCase(), style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 18))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: context.textPrimary)),
                const SizedBox(height: 4),
                Text(AppFormatters.dateTimeFull.format(item.date), style: TextStyle(color: context.textFaint, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7), borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(Strings.t(lang, item.income ? 'receive' : 'transfer'), style: TextStyle(color: context.textMuted)),
              NumberFlow(value: item.amount, locale: 'id_ID', format: NumberFlowFormat.currency(currencyCode: 'IDR', symbol: item.income ? '+Rp ' : '-Rp '), style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2, color: item.income ? const Color(0xFF24A148) : context.textPrimary)),
            ]),
          ),
          if (item.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(item.note, style: TextStyle(color: context.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  showTransactionForm(context, ref, item.income, existing: item);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(Strings.t(lang, 'edit')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteTransaction(context, ref, item);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(Strings.t(lang, 'delete')),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

void showTransactionLoanNotice(BuildContext context, WidgetRef ref, FinanceTransaction item) {
  final lang = ref.read(langProvider);
  final primary = Theme.of(context).colorScheme.primary;
  final isDark = context.isDark;
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle),
              child: Icon(SolarIconsOutline.usersGroupTwoRounded, color: primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.textPrimary)),
                const SizedBox(height: 4),
                Text(AppFormatters.dateTimeFull.format(item.date), style: TextStyle(color: context.textFaint, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7), borderRadius: BorderRadius.circular(18)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Strings.t(lang, 'loan_edit_from_panel_notice'),
                  style: TextStyle(color: context.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => LoanManagementPage(initialLoanId: item.loanId)));
              },
              icon: const Icon(SolarIconsOutline.usersGroupTwoRounded, size: 18),
              label: Text(Strings.t(lang, 'go_to_loans')),
            ),
          ),
        ]),
      ),
    ),
  );
}

void _confirmDeleteTransaction(BuildContext context, WidgetRef ref, FinanceTransaction item) {
  final lang = ref.read(langProvider);
  final isDark = context.isDark;
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: GlassContainer(
        shape: const LiquidRoundedRectangle(borderRadius: 28),
        useOwnLayer: true,
        quality: GlassQuality.premium,
        settings: LiquidGlassSettings(
          blur: 20,
          thickness: 24,
          glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.45) : const Color.fromRGBO(255, 255, 255, 0.22),
          whitenStrength: 0.0,
          lightIntensity: isDark ? 0.14 : 1.0,
          ambientStrength: isDark ? 0.09 : 0.55,
          saturation: isDark ? 1.6 : 1.9,
          refractiveIndex: isDark ? 0.2 : 1.85,
          chromaticAberration: isDark ? 0.0 : 2.2,
          fresnelStrength: isDark ? 0.12 : 1.0,
          glowIntensity: isDark ? 0.08 : 0.7,
          shadowElevation: isDark ? 1.5 : 4,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Strings.t(lang, 'delete_transaction_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 12),
              Text(Strings.t(lang, 'delete_transaction_confirm').replaceAll('{title}', item.title), style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? context.textMuted : const Color(0xFF4A4458))),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(Strings.t(lang, 'cancel'))),
              TextButton(
                onPressed: () {
                  final loanId = item.loanId;
                  if (loanId != null && item.category == 'Pinjaman Diberikan') {
                    ref.read(loansProvider.notifier).removeLoan(loanId);
                  } else {
                    if (loanId != null) {
                      ref.read(loansProvider.notifier).removePaymentByTransaction(loanId, item.id);
                    }
                    ref.read(transactionsProvider.notifier).remove(item);
                  }
                  Navigator.pop(dialogContext);
                },
                child: Text(Strings.t(lang, 'delete'), style: const TextStyle(color: Colors.redAccent)),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

Future<void> showCardForm({
  required BuildContext context,
  required WidgetRef ref,
  FinanceCard? existing,
  int? index,
}) async {
  final isEdit = existing != null;
  final name = TextEditingController(text: existing?.name ?? '');
  final initialDigits = existing != null ? existing.number.replaceAll(RegExp(r'[^0-9]'), '') : '';
  final number = TextEditingController(text: initialDigits);
  final balance = TextEditingController(
      text: existing != null ? AppFormatters.thousands.format(existing.initialBalance).replaceAll(',', '.') : '');
  final nameShakeKey = GlobalKey<ShakeFieldState>();
  final numberShakeKey = GlobalKey<ShakeFieldState>();
  String? nameError;
  String? numberError;
  final lang = ref.read(langProvider);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isEdit ? Strings.t(lang, 'edit_card') : Strings.t(lang, 'add_card'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 28, color: context.textPrimary)),
        const SizedBox(height: 18),
        ShakeField(
          key: nameShakeKey,
          child: TextField(controller: name, decoration: InputDecoration(labelText: Strings.t(lang, 'card_name'), errorText: nameError)),
        ),
        const SizedBox(height: 12),
        ShakeField(
          key: numberShakeKey,
          child: TextField(
            controller: number,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: Strings.t(lang, 'last_4_digits'), counterText: '', errorText: numberError),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: balance,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()],
          decoration: InputDecoration(labelText: Strings.t(lang, 'initial_balance'), prefixText: 'Rp '),
        ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          final hasNameError = name.text.trim().isEmpty;
          final hasNumberError = number.text.trim().length != 4;
          if (hasNameError || hasNumberError) {
            setModalState(() {
              nameError = hasNameError ? Strings.t(lang, 'field_required') : null;
              numberError = hasNumberError ? Strings.t(lang, 'field_required') : null;
            });
            if (hasNameError) nameShakeKey.currentState?.shake();
            if (hasNumberError) numberShakeKey.currentState?.shake();
            Future.delayed(const Duration(milliseconds: 3000), () {
              if (context.mounted) {
                setModalState(() {
                  nameError = null;
                  numberError = null;
                });
              }
            });
            return;
          }
          final formattedNumber = '**** ${number.text.trim()}';
          final balanceValue = double.tryParse(balance.text.replaceAll('.', '')) ?? 0;
          if (isEdit && index != null) {
            ref.read(cardsProvider.notifier).update(index, formattedNumber, name.text.trim(), initialBalance: balanceValue);
          } else {
            ref.read(cardsProvider.notifier).add(formattedNumber, name.text.trim(), initialBalance: balanceValue);
            ref.read(selectedCardProvider.notifier).state = ref.read(cardsProvider).length - 1;
          }
          Navigator.pop(sheetContext);
        }, child: Text(isEdit ? Strings.t(lang, 'save_changes') : Strings.t(lang, 'save_card')))),
      ]),
    )),
  );
}

class CardManagementPage extends ConsumerWidget {
  const CardManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final cards = ref.watch(cardsProvider);
    final loans = ref.watch(loansProvider);
    final isDark = context.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
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
                  Expanded(child: Text(Strings.t(lang, 'account_wallet'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary))),
                  GestureDetector(
                    onTap: () => showCardForm(context: context, ref: ref),
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.addCircle, size: 20, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                cacheExtent: 600,
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final card = cards[i];
                  return RepaintBoundary(
                    child: StaggeredReveal(
                    animate: false,
                    index: i,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                          child: Icon(SolarIconsOutline.card, color: primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(child: Text(card.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary))),
                                if (card.type == CardType.piutang) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: primary.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
                                    child: Text(Strings.t(lang, 'loans_title'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: primary)),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 4),
                              Text(card.number, style: TextStyle(color: context.textMuted, fontSize: 12)),
                              const SizedBox(height: 2),
                              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text('${Strings.t(lang, 'initial_balance')}: ', style: TextStyle(color: context.textFaint, fontSize: 11)),
                                NumberFlow(value: card.initialBalance, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textFaint, fontSize: 11, letterSpacing: -1.0)),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => showCardForm(context: context, ref: ref, existing: card, index: i),
                          icon: Icon(Icons.edit_outlined, size: 18, color: context.iconMuted),
                        ),
                        IconButton(
                          onPressed: (cards.length <= 1 || (card.type == CardType.piutang && loans.isNotEmpty)) ? null : () => _confirmDelete(context, ref, i, card),
                          icon: Icon(Icons.delete_outline, size: 18, color: (cards.length <= 1 || (card.type == CardType.piutang && loans.isNotEmpty)) ? context.textFaint : Colors.redAccent),
                        ),
                      ],
                    ),
                  )));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, int index, FinanceCard card) {
    final lang = ref.read(langProvider);
    final isDark = context.isDark;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassContainer(
          shape: const LiquidRoundedRectangle(borderRadius: 28),
          useOwnLayer: true,
          quality: GlassQuality.premium,
          settings: LiquidGlassSettings(
            blur: 20,
            thickness: 24,
            glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.45) : const Color.fromRGBO(255, 255, 255, 0.22),
            whitenStrength: 0.0,
            lightIntensity: isDark ? 0.14 : 1.0,
            ambientStrength: isDark ? 0.09 : 0.55,
            saturation: isDark ? 1.6 : 1.9,
            refractiveIndex: isDark ? 0.2 : 1.85,
            chromaticAberration: isDark ? 0.0 : 2.2,
            fresnelStrength: isDark ? 0.12 : 1.0,
            glowIntensity: isDark ? 0.08 : 0.7,
            shadowElevation: isDark ? 1.5 : 4,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Strings.t(lang, 'delete_card_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 12),
              Text(Strings.t(lang, 'delete_card_confirm').replaceAll('{name}', card.name), style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? context.textMuted : const Color(0xFF4A4458))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(Strings.t(lang, 'cancel'))),
                TextButton(
                  onPressed: () {
                    final selected = ref.read(selectedCardProvider);
                    ref.read(cardsProvider.notifier).remove(index);
                    final newLen = ref.read(cardsProvider).length;
                    if (selected != -1 && selected >= newLen) {
                      ref.read(selectedCardProvider.notifier).state = newLen - 1;
                    } else if (selected != -1 && index < selected) {
                      ref.read(selectedCardProvider.notifier).state = selected - 1;
                    }
                    Navigator.pop(dialogContext);
                  },
                  child: Text(Strings.t(lang, 'delete'), style: const TextStyle(color: Colors.redAccent)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class LoanManagementPage extends ConsumerStatefulWidget {
  final String? initialLoanId;
  const LoanManagementPage({super.key, this.initialLoanId});
  @override
  ConsumerState<LoanManagementPage> createState() => _LoanManagementPageState();
}

class _LoanManagementPageState extends ConsumerState<LoanManagementPage> {
  String filter = 'all';
  static const filterKeys = ['all', 'loan_active', 'loan_paid', 'loan_inactive'];
  bool _autoOpenHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLoanId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenDetail());
    }
  }

  void _maybeAutoOpenDetail() {
    if (_autoOpenHandled || !mounted) return;
    final loanId = widget.initialLoanId;
    if (loanId == null) return;
    final loans = ref.read(loansProvider);
    final match = loans.where((l) => l.id == loanId);
    if (match.isEmpty) return;
    _autoOpenHandled = true;
    showLoanDetail(context, ref, match.first);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final loans = ref.watch(loansProvider);
    final cards = ref.watch(cardsProvider);
    final isDark = context.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    final tertiary = Theme.of(context).colorScheme.tertiary;
    final filtered = loans.where((l) {
      if (filter == 'all') return true;
      if (filter == 'loan_active') return l.status == LoanStatus.active;
      if (filter == 'loan_paid') return l.status == LoanStatus.paid;
      return l.status == LoanStatus.inactive;
    }).toList();
    final totalOutstanding = loans.where((l) => l.status != LoanStatus.paid).fold<double>(0, (a, l) => a + l.remainingPrincipal);
    final totalInterest = loans.fold<double>(0, (a, l) => a + l.totalInterestCollected);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
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
                  Expanded(child: Text(Strings.t(lang, 'loans_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textPrimary))),
                  GestureDetector(
                    onTap: () => showLoanForm(context: context, ref: ref),
                    child: LiquidGlass(
                      borderRadius: 999,
                      tint: isDark ? Colors.black : null,
                      intensity: isDark ? 1.6 : 1.0,
                      borderColor: isDark ? context.borderColor : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(SolarIconsOutline.addCircle, size: 20, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RepaintBoundary(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.borderColor)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(Strings.t(lang, 'total_outstanding'), style: TextStyle(color: context.textMuted, fontSize: 11)),
                          const SizedBox(height: 6),
                          NumberFlow(value: totalOutstanding, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: -0.2)),
                        ]),
                      ),
                      Container(width: 1, height: 36, color: context.borderColor),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(Strings.t(lang, 'total_interest_collected'), style: TextStyle(color: context.textMuted, fontSize: 11)),
                            const SizedBox(height: 6),
                            NumberFlow(value: totalInterest, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: const TextStyle(fontFamily: 'Satoshi', color: Color(0xFF24A148), fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: -0.2)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: filterKeys
                      .map<Widget>((k) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(k == 'all' ? Strings.t(lang, 'filter_all') : Strings.t(lang, k)),
                              selected: filter == k,
                              onSelected: (_) => setState(() => filter = k),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(Strings.t(lang, 'no_loans_yet'), style: TextStyle(color: context.textMuted)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      cacheExtent: 600,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final loan = filtered[i];
                        final sourceName = (loan.sourceCardIndex >= 0 && loan.sourceCardIndex < cards.length) ? cards[loan.sourceCardIndex].name : '';
                        return StaggeredReveal(
                          index: i,
                          child: GestureDetector(
                            onTap: () => showLoanDetail(context, ref, loan),
                            child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: context.cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.borderColor)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                                      child: Icon(SolarIconsOutline.usersGroupTwoRounded, color: primary, size: 20),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(loan.borrowerName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
                                          const SizedBox(height: 4),
                                          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                                            Text('${Strings.t(lang, 'remaining_principal')}: ', style: TextStyle(color: context.textMuted, fontSize: 12)),
                                            NumberFlow(value: loan.remainingPrincipal, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textMuted, fontSize: 12, letterSpacing: -0.1)),
                                          ]),
                                          if (sourceName.isNotEmpty) Text(sourceName, style: TextStyle(color: context.textFaint, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (loan.status == LoanStatus.active ? const Color(0xFF24A148) : loan.status == LoanStatus.paid ? primary : Colors.grey).withOpacity(0.14),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            Strings.t(lang, loan.status == LoanStatus.active ? 'loan_active' : loan.status == LoanStatus.paid ? 'loan_paid' : 'loan_inactive'),
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: loan.status == LoanStatus.active ? const Color(0xFF24A148) : loan.status == LoanStatus.paid ? primary : Colors.grey),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, children: [
                                          Text('${loan.interestPercent}% / ', style: TextStyle(color: context.textFaint, fontSize: 11, fontWeight: FontWeight.w600)),
                                          NumberFlow(value: loan.currentInterest, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                                        ]),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: context.borderColor),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => showLoanForm(context: context, ref: ref, existing: loan),
                                      style: TextButton.styleFrom(foregroundColor: primary),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: Text(Strings.t(lang, 'edit'), style: const TextStyle(fontSize: 12)),
                                    ),
                                    TextButton.icon(
                                      onPressed: loan.status == LoanStatus.paid ? null : () => ref.read(loansProvider.notifier).toggleActive(loan.id),
                                      icon: Icon(loan.status == LoanStatus.inactive ? Icons.play_arrow : Icons.pause, size: 16),
                                      label: Text(Strings.t(lang, loan.status == LoanStatus.inactive ? 'loan_active' : 'toggle_active'), style: const TextStyle(fontSize: 12)),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _confirmDeleteLoan(context, ref, loan),
                                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                      icon: const Icon(Icons.delete_outline, size: 16),
                                      label: Text(Strings.t(lang, 'delete'), style: const TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteLoan(BuildContext context, WidgetRef ref, Loan loan) {
    final lang = ref.read(langProvider);
    final isDark = context.isDark;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassContainer(
          shape: const LiquidRoundedRectangle(borderRadius: 28),
          useOwnLayer: true,
          quality: GlassQuality.premium,
          settings: LiquidGlassSettings(
            blur: 20,
            thickness: 24,
            glassColor: isDark ? const Color.fromRGBO(0, 0, 0, 0.45) : const Color.fromRGBO(255, 255, 255, 0.22),
            whitenStrength: 0.0,
            lightIntensity: isDark ? 0.14 : 1.0,
            ambientStrength: isDark ? 0.09 : 0.55,
            saturation: isDark ? 1.6 : 1.9,
            refractiveIndex: isDark ? 0.2 : 1.85,
            chromaticAberration: isDark ? 0.0 : 2.2,
            fresnelStrength: isDark ? 0.12 : 1.0,
            glowIntensity: isDark ? 0.08 : 0.7,
            shadowElevation: isDark ? 1.5 : 4,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Strings.t(lang, 'delete_loan_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 12),
              Text(Strings.t(lang, 'delete_loan_confirm').replaceAll('{name}', loan.borrowerName), style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? context.textMuted : const Color(0xFF4A4458))),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(Strings.t(lang, 'cancel'))),
                TextButton(
                  onPressed: () {
                    ref.read(loansProvider.notifier).removeLoan(loan.id);
                    Navigator.pop(dialogContext);
                  },
                  child: Text(Strings.t(lang, 'delete'), style: const TextStyle(color: Colors.redAccent)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}



Future<void> showLoanForm({required BuildContext context, required WidgetRef ref, Loan? existing}) async {
  final isEdit = existing != null;
  final lang = ref.read(langProvider);
  final nameCtrl = TextEditingController(text: existing?.borrowerName ?? '');
  final principalCtrl = TextEditingController(text: existing != null ? AppFormatters.thousands.format(existing.principal).replaceAll(',', '.') : '');
  final percentCtrl = TextEditingController(text: existing != null ? existing.interestPercent.toString() : '10');
  final noteCtrl = TextEditingController(text: existing?.note ?? '');
  LoanInterestType interestType = existing?.interestType ?? LoanInterestType.declining;
  DateTime startDate = existing?.startDate ?? DateTime.now();
  final nameShakeKey = GlobalKey<ShakeFieldState>();
  final principalShakeKey = GlobalKey<ShakeFieldState>();
  String? nameError;
  String? principalError;
  final cards = ref.read(cardsProvider);
  final nonPiutangCards = cards.asMap().entries.where((e) => e.value.type != CardType.piutang).toList();
  int sourceCardIndex = existing?.sourceCardIndex ?? (nonPiutangCards.isNotEmpty ? nonPiutangCards.first.key : 0);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isEdit ? Strings.t(lang, 'edit') : Strings.t(lang, 'add_loan'), style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 28, color: context.textPrimary)),
          const SizedBox(height: 18),
          ShakeField(key: nameShakeKey, child: TextField(controller: nameCtrl, decoration: InputDecoration(labelText: Strings.t(lang, 'borrower_name'), errorText: nameError))),
          const SizedBox(height: 12),
          ShakeField(
            key: principalShakeKey,
            child: TextField(
              controller: principalCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsInputFormatter()],
              decoration: InputDecoration(labelText: Strings.t(lang, 'principal_amount'), prefixText: 'Rp ', errorText: principalError),
            ),
          ),
          if (!isEdit) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: sourceCardIndex,
              decoration: InputDecoration(labelText: Strings.t(lang, 'loan_source_card')),
              items: nonPiutangCards.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.name))).toList(),
              onChanged: (v) => setModalState(() => sourceCardIndex = v!),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: percentCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            decoration: InputDecoration(labelText: Strings.t(lang, 'interest_percent'), suffixText: '%'),
          ),
          const SizedBox(height: 12),
          Text(Strings.t(lang, 'interest_type'), style: TextStyle(fontSize: 12, color: context.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ChoiceChip(
                label: Text(Strings.t(lang, 'interest_declining'), style: const TextStyle(fontSize: 11)),
                selected: interestType == LoanInterestType.declining,
                onSelected: (_) => setModalState(() => interestType = LoanInterestType.declining),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: Text(Strings.t(lang, 'interest_flat'), style: const TextStyle(fontSize: 11)),
                selected: interestType == LoanInterestType.flat,
                onSelected: (_) => setModalState(() => interestType = LoanInterestType.flat),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (!isEdit)
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (picked != null) setModalState(() => startDate = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: Strings.t(lang, 'date')),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: context.iconMuted),
                  const SizedBox(width: 10),
                  Text(AppFormatters.dateOnly.format(startDate), style: TextStyle(fontSize: 14, color: context.textPrimary, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          if (!isEdit) const SizedBox(height: 12),
          TextField(controller: noteCtrl, decoration: InputDecoration(labelText: Strings.t(lang, 'note_optional'))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final hasNameError = nameCtrl.text.trim().isEmpty;
                final principalValue = double.tryParse(principalCtrl.text.replaceAll('.', '')) ?? 0;
                final hasPrincipalError = principalValue <= 0;
                if (hasNameError || hasPrincipalError) {
                  setModalState(() {
                    nameError = hasNameError ? Strings.t(lang, 'field_required') : null;
                    principalError = hasPrincipalError ? Strings.t(lang, 'field_required') : null;
                  });
                  if (hasNameError) nameShakeKey.currentState?.shake();
                  if (hasPrincipalError) principalShakeKey.currentState?.shake();
                  Future.delayed(const Duration(milliseconds: 3000), () {
                    if (context.mounted) setModalState(() { nameError = null; principalError = null; });
                  });
                  return;
                }
                final percentValue = double.tryParse(percentCtrl.text) ?? 0;
                if (isEdit) {
                  ref.read(loansProvider.notifier).updateLoan(existing.id, borrowerName: nameCtrl.text.trim(), principal: principalValue, interestPercent: percentValue, interestType: interestType, note: noteCtrl.text.trim());
                } else {
                  ref.read(loansProvider.notifier).addLoan(
                        borrowerName: nameCtrl.text.trim(),
                        principal: principalValue,
                        interestPercent: percentValue,
                        interestType: interestType,
                        startDate: startDate,
                        note: noteCtrl.text.trim(),
                        sourceCardIndex: sourceCardIndex,
                      );
                }
                Navigator.pop(sheetContext);
              },
              child: Text(isEdit ? Strings.t(lang, 'save_changes') : Strings.t(lang, 'save_loan')),
            ),
          ),
        ]),
      ),
    )),
  );
}

Future<void> showLoanDetail(BuildContext context, WidgetRef ref, Loan loan) async {
  final lang = ref.read(langProvider);
  final primary = Theme.of(context).colorScheme.primary;
  final isDark = context.isDark;
  final tertiary = Theme.of(context).colorScheme.tertiary;
  final interestPaymentCount = loan.payments.where((p) => p.interestAmount > 0).length;
  final bep = estimateLoanBEP(loan);
  final sortedPayments = [...loan.payments]..sort((a, b) => b.date.compareTo(a.date));
  final statusColor = loan.status == LoanStatus.active ? const Color(0xFF24A148) : loan.status == LoanStatus.paid ? primary : Colors.grey;
  final subtleBg = isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: context.borderColor, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: isDark ? primary.withOpacity(0.18) : tertiary, shape: BoxShape.circle),
                  child: Icon(SolarIconsOutline.usersGroupTwoRounded, color: primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.borrowerName, style: TextStyle(fontFamily: 'DM Serif Display', fontSize: 21, color: context.textPrimary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          Strings.t(lang, loan.status == LoanStatus.active ? 'loan_active' : loan.status == LoanStatus.paid ? 'loan_paid' : 'loan_inactive'),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showLoanForm(context: context, ref: ref, existing: loan);
                  },
                  child: LiquidGlass(
                    borderRadius: 999,
                    tint: isDark ? Colors.black : null,
                    intensity: isDark ? 1.6 : 1.0,
                    borderColor: isDark ? context.borderColor : null,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.edit_outlined, size: 18, color: primary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: subtleBg, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Strings.t(lang, 'principal_label'), style: TextStyle(color: context.textMuted, fontSize: 11)),
                    const SizedBox(height: 6),
                    NumberFlow(value: loan.principal, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: -0.2)),
                  ]),
                ),
                Container(width: 1, height: 34, color: context.borderColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Strings.t(lang, 'remaining_principal'), style: TextStyle(color: context.textMuted, fontSize: 11)),
                      const SizedBox(height: 6),
                      NumberFlow(value: loan.remainingPrincipal, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: 'Rp '), style: TextStyle(fontFamily: 'Satoshi', color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: -0.2)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _LoanDetailStat(
                  icon: Icons.calendar_today_outlined,
                  label: Strings.t(lang, 'loan_date'),
                  value: AppFormatters.dateOnly.format(loan.startDate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LoanDetailStat(
                  icon: Icons.flag_outlined,
                  label: Strings.t(lang, 'target_bep'),
                  value: bep.reached
                      ? Strings.t(lang, 'target_bep_reached')
                      : (bep.date != null ? AppFormatters.dateOnly.format(bep.date!) : Strings.t(lang, 'target_bep_unavailable')),
                  valueColor: bep.reached ? const Color(0xFF24A148) : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _LoanDetailStat(
                  icon: Icons.autorenew,
                  label: Strings.t(lang, 'interest_payment_count'),
                  value: '$interestPaymentCount×',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LoanDetailStat(
                  icon: SolarIconsOutline.wallet,
                  label: Strings.t(lang, 'total_interest_collected'),
                  value: rupiah(loan.totalInterestCollected),
                  valueColor: const Color(0xFF24A148),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            Text(Strings.t(lang, 'payment_history'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
            const SizedBox(height: 10),
            Expanded(
              child: sortedPayments.isEmpty
                  ? Center(child: Text(Strings.t(lang, 'no_payments_yet'), style: TextStyle(color: context.textMuted, fontSize: 13)))
                  : ListView.separated(
                      controller: scrollController,
                      cacheExtent: 400,
                      itemCount: sortedPayments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = sortedPayments[i];
                        final isInterest = p.interestAmount > 0;
                        final amount = isInterest ? p.interestAmount : p.principalAmount;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: subtleBg, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: (isInterest ? const Color(0xFF24A148) : primary).withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(isInterest ? SolarIconsOutline.wallet : SolarIconsOutline.card, size: 15, color: isInterest ? const Color(0xFF24A148) : primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(Strings.t(lang, isInterest ? 'payment_interest_label' : 'payment_principal_label'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(AppFormatters.dateOnly.format(p.date), style: TextStyle(fontSize: 11, color: context.textFaint)),
                                ],
                              ),
                            ),
                            NumberFlow(value: amount, locale: 'id_ID', format: const NumberFlowFormat.currency(currencyCode: 'IDR', symbol: '+Rp '), style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: -0.1, color: isInterest ? const Color(0xFF24A148) : context.textPrimary)),
                          ]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LoanDetailStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _LoanDetailStat({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF1EEF7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: primary),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 10.5, color: context.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: valueColor ?? context.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class StaggeredReveal extends StatefulWidget {
  final Widget child;
  final int index;
  final bool animate;
  final bool stagger;
  const StaggeredReveal({super.key, required this.child, required this.index, this.animate = true, this.stagger = false});
  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.82, curve: Curves.easeOut));
  late final Animation<double> _slide = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Key _visibilityKey = widget.key ?? UniqueKey();
  bool _triggered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleVisibility(VisibilityInfo info) {
    if (_triggered || !mounted) return;
    if (info.visibleFraction <= 0.08) return;
    _triggered = true;
    final delay = widget.stagger ? Duration(milliseconds: 45 * (widget.index % 6)) : Duration.zero;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.animate) return widget.child;
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _handleVisibility,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => Opacity(
            opacity: _fade.value,
            child: Transform.translate(
              offset: Offset(0, (1 - _slide.value) * 26),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

String rupiah(double value) => AppFormatters.rupiah(value);
