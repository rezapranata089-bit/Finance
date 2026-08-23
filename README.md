# My Finance

Aplikasi catatan keuangan personal berbasis Flutter.

## Build APK dari Termux melalui GitHub

1. Push project ini ke GitHub.
2. Buka tab **Actions**.
3. Pilih workflow **Build My Finance APK**.
4. Tekan **Run workflow**.
5. Tunggu sampai selesai.
6. Buka hasil workflow dan download artifact **my-finance-apk**.

Workflow akan:

- Memasang Flutter stable di runner GitHub.
- Membuat project Android jika folder Android belum ada.
- Mengambil dependency Flutter.
- Menjalankan formatter, analyzer, dan test.
- Membuild APK release.
- Mengunggah APK sebagai artifact.

## Build otomatis

Workflow juga berjalan otomatis setiap kali ada perubahan di `flutter/my_finance/`.

## Catatan

APK yang dihasilkan masih berupa release APK unsigned. Untuk distribusi Google Play, tambahkan signing key Android melalui GitHub Secrets dan konfigurasi signing pada project Android.