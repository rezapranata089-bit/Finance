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
# Percobaan pertama (-keep com.google.mlkit.** & com.google.android.gms.**)
# TERNYATA BELUM CUKUP LUAS — kali ini keep rules diperluas eksplisit ke
# sub-package internal yang dipakai ML Kit Text Recognition & Play Services
# Tasks/Common/Dynamite, plus -keepclassmembers agar constructor & field
# yang diakses reflektif tidak ikut di-strip R8. PENTING: rules ini hanya
# berlaku setelah APK di-build ULANG (flutter build apk --release) dan
# di-install ulang di perangkat — mapping id yang identik dengan build
# sebelumnya berarti APK yang sedang diuji belum memakai rules terbaru ini.
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep interface com.google.android.gms.** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.dynamite.** { *; }
-keepclassmembers class com.google.mlkit.** { *; }
-keepclassmembers class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.odml.**
