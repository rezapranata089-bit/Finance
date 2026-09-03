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