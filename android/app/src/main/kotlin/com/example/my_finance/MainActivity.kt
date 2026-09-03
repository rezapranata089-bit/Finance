package com.example.my_finance

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installCrashHandler()
    }

    // Menangkap uncaught exception Java/Kotlin (termasuk kegagalan native
    // codec yang naik sebagai RuntimeException, mis. dari
    // MediaMetadataRetriever/decoder OEM tertentu) sebelum proses berhenti,
    // lalu menulisnya ke filesDir agar bisa dibaca ulang di halaman Log
    // Aplikasi. Tidak menangkap crash native murni (segfault C/C++) karena
    // itu di luar jangkauan JVM.
    // PENTING: getApplicationDocumentsDirectory() di sisi Dart (path_provider)
    // pada Android me-resolve ke subfolder "app_flutter" DI DALAM filesDir,
    // bukan filesDir itu sendiri. Sebelumnya kode ini menulis langsung ke
    // filesDir, sehingga file log native tidak pernah ketemu oleh
    // _readCombinedCrashLog() di Dart (folder berbeda) — akibatnya section
    // native (termasuk log GalleryPicker) tidak pernah tampil di halaman
    // "Log Aplikasi". Helper ini memastikan kedua sisi menulis/membaca ke
    // folder yang sama persis.
    private fun nativeCrashLogFile(): File {
        val dir = File(filesDir, "app_flutter")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "crash_log_native.txt")
    }

    private fun installCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                nativeCrashLogFile().appendText("[$timestamp] Thread: ${thread.name}\n$sw\n")
            } catch (_: Exception) {
            }
            defaultHandler?.uncaughtException(thread, throwable)
        }
    }

    // Menulis info debug pemilihan galeri (jumlah & nama paket kandidat yang
    // ditemukan/tereksklusi) ke file crash log yang sama, supaya bisa
    // diperiksa lewat halaman "Log Aplikasi" tanpa perlu USB debugging.
    // Berguna untuk mendiagnosis kenapa galeri asli tidak terdeteksi di
    // perangkat OEM tertentu (mis. Infinix/Tecno/itel berbasis XOS).
    private fun logGalleryDebug(message: String) {
        try {
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            nativeCrashLogFile().appendText("[$timestamp] GalleryPicker: $message\n")
        } catch (_: Exception) {
        }
    }

    private val channelName = "com.example.my_finance/gallery_picker"
    private val pickImageRequestCode = 9001
    private val pickMediaRequestCode = 9002
    private var pendingResult: MethodChannel.Result? = null

    // Menampung satu aplikasi galeri kandidat beserta Intent siap-pakai untuk
    // membukanya. Disimpan sebagai Intent lengkap (bukan hanya ResolveInfo)
    // karena kandidat bisa datang dari dua jenis intent berbeda
    // (ACTION_GET_CONTENT atau ACTION_PICK) tergantung bagaimana aplikasi
    // tersebut mendaftar di sistem.
    private data class GalleryCandidate(
        val packageName: String,
        val className: String,
        val launchIntent: Intent
    )

    private val photoPickerMarkers = listOf("photopicker", "media.module")

    private fun isPhotoPicker(pkg: String, cls: String): Boolean =
        photoPickerMarkers.any { marker -> pkg.contains(marker, ignoreCase = true) || cls.contains(marker, ignoreCase = true) }

    // Mengumpulkan kandidat aplikasi galeri "asli" (bukan Photo Picker bawaan
    // Android) dengan mencoba DUA mekanisme intent sekaligus:
    //
    // 1. ACTION_GET_CONTENT + CATEGORY_OPENABLE — didukung oleh galeri
    //    stok/AOSP dan sebagian besar aplikasi galeri modern.
    // 2. ACTION_PICK dengan MediaStore content URI — mekanisme lama yang
    //    justru lebih universal didukung oleh galeri bawaan pabrikan (mis.
    //    Gallery bawaan Infinix/Tecno/itel berbasis XOS), yang seringkali
    //    TIDAK mendaftarkan diri untuk ACTION_GET_CONTENT sama sekali. Tanpa
    //    probe kedua ini, di perangkat seperti itu daftar kandidat bisa
    //    kosong dan aplikasi jatuh ke Photo Picker sistem alih-alih galeri
    //    bawaan HP — inilah penyebab galeri yang terbuka bukan galeri asli.
    //
    // Kedua mekanisme di-dedupe berdasarkan package+class supaya aplikasi
    // yang sama tidak muncul dua kali di chooser.
    private fun resolveGalleryCandidates(imageOnly: Boolean): List<GalleryCandidate> {
        val candidates = LinkedHashMap<String, GalleryCandidate>()

        fun addFrom(probeIntent: Intent, launchIntentBuilder: (String, String) -> Intent) {
            val resolved = packageManager.queryIntentActivities(probeIntent, PackageManager.MATCH_DEFAULT_ONLY)
            for (info in resolved) {
                val pkg = info.activityInfo.packageName
                val cls = info.activityInfo.name
                if (isPhotoPicker(pkg, cls)) continue
                val key = "$pkg/$cls"
                if (candidates.containsKey(key)) continue
                candidates[key] = GalleryCandidate(pkg, cls, launchIntentBuilder(pkg, cls))
            }
        }

        if (imageOnly) {
            addFrom(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
            ) { pkg, cls ->
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    setClassName(pkg, cls)
                }
            }
            addFrom(
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            ) { pkg, cls ->
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                    setClassName(pkg, cls)
                }
            }
        } else {
            // queryIntentActivities ignores EXTRA_MIME_TYPES and only looks
            // at the intent's literal "type" field, so probe image/* and
            // video/* separately via GET_CONTENT, then also probe
            // ACTION_PICK for both MediaStore URIs to catch OEM galleries
            // that skip GET_CONTENT entirely.
            addFrom(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
            ) { pkg, cls ->
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                    addCategory(Intent.CATEGORY_OPENABLE)
                    setClassName(pkg, cls)
                }
            }
            addFrom(
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "video/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
            ) { pkg, cls ->
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                    addCategory(Intent.CATEGORY_OPENABLE)
                    setClassName(pkg, cls)
                }
            }
            addFrom(
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            ) { pkg, cls ->
                Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                    setClassName(pkg, cls)
                }
            }
            addFrom(
                Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            ) { pkg, cls ->
                Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI).apply {
                    setClassName(pkg, cls)
                }
            }
        }

        val result = candidates.values.toList()
        logGalleryDebug("imageOnly=$imageOnly found=${result.size} pkgs=${result.joinToString { "${it.packageName}/${it.className}" }}")
        return result
    }

    // Membuka kandidat langsung jika hanya ada satu, menampilkan chooser
    // custom jika lebih dari satu (supaya Photo Picker sistem tidak pernah
    // ikut muncul), atau fallback ke intent sistem default jika benar-benar
    // tidak ada galeri "asli" yang terdeteksi sama sekali.
    private fun launchGalleryChooser(candidates: List<GalleryCandidate>, requestCode: Int, chooserTitle: String) {
        when {
            candidates.size == 1 -> {
                startActivityForResult(candidates.first().launchIntent, requestCode)
            }
            candidates.size > 1 -> {
                val intents = candidates.map { it.launchIntent }
                val chooser = Intent.createChooser(intents.first(), chooserTitle).apply {
                    putExtra(Intent.EXTRA_INITIAL_INTENTS, intents.drop(1).toTypedArray())
                }
                startActivityForResult(chooser, requestCode)
            }
            else -> {
                // Tidak ada galeri "asli" yang terdeteksi sama sekali (mis.
                // Pixel / near-stock Android tanpa galeri terpisah).
                // Fallback ke GET_CONTENT sistem default, yang akan membuka
                // Photo Picker atau Google Photos.
                logGalleryDebug("FALLBACK ke System Photo Picker (0 kandidat ditemukan) requestCode=$requestCode")
                val fallbackIntent = if (requestCode == pickImageRequestCode) {
                    Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                } else {
                    Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                }
                startActivityForResult(fallbackIntent, requestCode)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "pickImageWithChooser") {
                pendingResult = result
                launchGalleryChooser(resolveGalleryCandidates(imageOnly = true), pickImageRequestCode, "Pilih Foto Profil")
            } else if (call.method == "pickMediaWithChooser") {
                pendingResult = result
                launchGalleryChooser(resolveGalleryCandidates(imageOnly = false), pickMediaRequestCode, "Pilih Foto atau Video Profil")
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickImageRequestCode) {
            val result = pendingResult
            pendingResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result?.success(null)
                return
            }
            val uri: Uri = data.data!!
            try {
                val inputStream = contentResolver.openInputStream(uri)
                if (inputStream == null) {
                    result?.error("READ_FAILED", "Tidak bisa membaca gambar yang dipilih", null)
                    return
                }
                val outputFile = File(cacheDir, "picked_profile_${System.currentTimeMillis()}.jpg")
                FileOutputStream(outputFile).use { output ->
                    inputStream.copyTo(output)
                }
                inputStream.close()
                result?.success(outputFile.absolutePath)
            } catch (e: Exception) {
                result?.error("COPY_FAILED", e.message, null)
            }
        } else if (requestCode == pickMediaRequestCode) {
            val result = pendingResult
            pendingResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result?.success(null)
                return
            }
            val uri: Uri = data.data!!
            try {
                // Determine whether the picked file is an image or a video so
                // the Dart side can route it to the right (crop vs trim+crop) flow.
                val mimeType = contentResolver.getType(uri) ?: ""
                val isVideo = mimeType.startsWith("video/")
                val extension = if (isVideo) "mp4" else "jpg"
                val inputStream = contentResolver.openInputStream(uri)
                if (inputStream == null) {
                    result?.error("READ_FAILED", "Tidak bisa membaca berkas yang dipilih", null)
                    return
                }
                val outputFile = File(cacheDir, "picked_profile_media_${System.currentTimeMillis()}.$extension")
                FileOutputStream(outputFile).use { output ->
                    inputStream.copyTo(output)
                }
                inputStream.close()
                result?.success(outputFile.absolutePath)
            } catch (e: Exception) {
                result?.error("COPY_FAILED", e.message, null)
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
