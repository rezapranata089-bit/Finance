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

# cunning_document_scanner: memakai Google Play services ML Kit Document
# Scanner (com.google.mlkit.vision.documentscanner) untuk auto-crop &
# perspective-correction saat memindai struk. google_mlkit_text_recognition
# sudah TIDAK dipakai lagi — OCR sekarang memakai Tesseract offline
# (flutter_tesseract_ocr), sehingga seluruh rule khusus text recognition
# yang sebelumnya ada di sini (chinese/devanagari/japanese/korean & keep
# class vision.text.**) sudah dihapus karena tidak relevan lagi.
#
# Class document scanner tetap di-keep sebagai langkah preventif,
# berdasarkan pengalaman sebelumnya: R8 pernah menyebabkan fitur ML Kit
# lain crash di build release karena class terkait ikut terpangkas walau
# sebenarnya dipanggil secara native/reflection. Infrastruktur Play
# Services generik (tasks/common api/dynamite) tetap di-keep karena dipakai
# document scanner untuk memuat modul & menjalankan callback.
-keep class com.google.mlkit.vision.documentscanner.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_document_scanner.** { *; }
-keep class com.google.android.gms.common.internal.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.dynamite.** { *; }
-keep class com.google.android.gms.common.GoogleApiAvailability { *; }
-keep class com.google.android.gms.common.ConnectionResult { *; }
-dontwarn com.google.mlkit.vision.documentscanner.**
-dontwarn com.google.android.gms.**
