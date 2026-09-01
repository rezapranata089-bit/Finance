package com.example.my_finance

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.my_finance/gallery_picker"
    private val pickImageRequestCode = 9001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "pickImageWithChooser") {
                pendingResult = result

                val baseIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }

                // Ask the system for every app that can handle this intent,
                // instead of maintaining a hardcoded per-brand package list.
                // This adapts automatically to any device/OEM without needing
                // future updates when new phone brands appear.
                val resolvedActivities = packageManager.queryIntentActivities(baseIntent, PackageManager.MATCH_DEFAULT_ONLY)

                // The Android Photo Picker (styled like Google Photos, active
                // on Android 11+/13+) always shows up under a component whose
                // package or class name contains one of these markers,
                // regardless of device brand. Filter it out dynamically.
                val photoPickerMarkers = listOf("photopicker", "media.module")
                fun isPhotoPicker(pkg: String, cls: String): Boolean =
                    photoPickerMarkers.any { marker -> pkg.contains(marker, ignoreCase = true) || cls.contains(marker, ignoreCase = true) }

                val realGalleryApps = resolvedActivities.filter { info ->
                    !isPhotoPicker(info.activityInfo.packageName, info.activityInfo.name)
                }

                when {
                    realGalleryApps.size == 1 -> {
                        // Exactly one real gallery/file app found: open it
                        // directly, with no dialog at all.
                        val info = realGalleryApps.first().activityInfo
                        val directIntent = Intent(baseIntent).apply {
                            setClassName(info.packageName, info.name)
                        }
                        startActivityForResult(directIntent, pickImageRequestCode)
                    }
                    realGalleryApps.size > 1 -> {
                        // Multiple real candidates: show a chooser built only
                        // from those, so the Photo Picker never appears as
                        // an option even if it's technically installed.
                        val targetedIntents = realGalleryApps.map { info ->
                            Intent(baseIntent).apply {
                                setClassName(info.activityInfo.packageName, info.activityInfo.name)
                            }
                        }
                        val chooser = Intent.createChooser(targetedIntents.first(), "Pilih Foto Profil").apply {
                            putExtra(Intent.EXTRA_INITIAL_INTENTS, targetedIntents.drop(1).toTypedArray())
                        }
                        startActivityForResult(chooser, pickImageRequestCode)
                    }
                    else -> {
                        // No non-Photo-Picker app found (e.g. Pixel / near-
                        // stock Android with no separate gallery app). Fall
                        // back to whatever the system offers, which will be
                        // the Photo Picker or Google Photos itself.
                        startActivityForResult(baseIntent, pickImageRequestCode)
                    }
                }
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
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
