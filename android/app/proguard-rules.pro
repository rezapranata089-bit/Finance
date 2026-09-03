# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep annotations & generic signatures (aman untuk plugin yang pakai reflection)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes Exceptions
-keepattributes InnerClasses

# Jangan warning untuk class Android yang di-strip dev tools
-dontwarn io.flutter.embedding.**

# google_mlkit_text_recognition: plugin ini mereferensikan class recognizer
# untuk SEMUA script (Cina, Jepang, Korea, Devanagari) walau app ini cuma
# memakai TextRecognitionScript.latin (lihat receipt_scanner.dart). Karena
# dependency Gradle untuk script-script lain sengaja tidak ditambahkan
# (tidak dibutuhkan), R8 gagal minify di build release karena tidak
# menemukan class-class tersebut. -dontwarn di sini aman: class-class itu
# memang tidak pernah dipanggil selama hanya script Latin yang dipakai.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# FIX: "Pindai Struk" gagal/crash saat processImage() di build release
# (R8/minify aktif) dengan error "Attempt to invoke virtual method
# 'java.lang.Class java.lang.Object.getClass()' on a null object reference".
# Percobaan pertama (-keep com.google.mlkit.** & com.google.android.gms.**
# secara PENUH, mencakup seluruh sub-paket) berhasil memperbaiki crash-nya,
# TAPI membuat R8 tidak boleh memangkas kode yang tidak dipakai dari kedua
# namespace besar itu, sehingga jumlah class/method yang harus di-dex jauh
# lebih banyak dari yang sebenarnya dipakai aplikasi — inilah yang membuat
# waktu build APK release melonjak dari ~3 menit menjadi ~6 menit.
#
# Versi ini mempersempit keep HANYA ke sub-paket yang benar-benar dipakai
# oleh google_mlkit_text_recognition (script Latin) & google_mlkit_commons:
# API publik ML Kit vision/text/common, implementasi internal ML Kit di
# dalam GMS, serta infrastruktur Play Services (tasks/common api/dynamite)
# yang dipakai ML Kit untuk memuat model & menjalankan callback. Paket GMS
# lain yang tidak dipakai sama sekali (auth, ads, maps, wallet, dst) TIDAK
# ikut di-keep, sehingga R8 tetap bebas memangkasnya seperti biasa.
#
# PENTING: jika crash NPE offline scan ("Pindai Struk") muncul lagi setelah
# ini di-build & diuji ulang di perangkat yang bermasalah, revert ke versi
# sebelumnya (keep penuh com.google.mlkit.** & com.google.android.gms.**)
# — build lebih lambat tapi terbukti stabil.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.common.internal.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.dynamite.** { *; }
-keep class com.google.android.gms.common.GoogleApiAvailability { *; }
-keep class com.google.android.gms.common.ConnectionResult { *; }
-keepclassmembers class com.google.mlkit.** { *; }
-keepclassmembers class com.google.android.gms.internal.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.odml.**
