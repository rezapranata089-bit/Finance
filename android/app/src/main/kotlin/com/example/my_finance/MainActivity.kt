package com.example.my_finance

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
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

                // Samsung Galaxy devices (including A-series like A55) ship
                // their own Gallery app under this package. Target it
                // directly so it opens with no picker/chooser dialog at all.
                val samsungGalleryPackage = "com.sec.android.gallery3d"
                val directIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    setPackage(samsungGalleryPackage)
                }
                val samsungGalleryAvailable = directIntent.resolveActivity(packageManager) != null

                if (samsungGalleryAvailable) {
                    startActivityForResult(directIntent, pickImageRequestCode)
                } else {
                    // Fallback: Samsung Gallery not found under the expected
                    // package on this device/ROM variant. Show a normal
                    // chooser, excluding the Android Photo Picker (which
                    // intercepts ACTION_GET_CONTENT for image/* on Android
                    // 11+/13+ and looks like Google Photos) so a real app
                    // list shows instead.
                    val fallbackIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    val chooser = Intent.createChooser(fallbackIntent, "Pilih Foto Profil")
                    val excludedComponents = arrayOf(
                        ComponentName("com.google.android.providers.media.module", "com.android.providers.media.photopicker.PhotoPickerActivity"),
                        ComponentName("com.android.providers.media.module", "com.android.providers.media.photopicker.PhotoPickerActivity"),
                        ComponentName("com.google.android.providers.media.module", "com.android.providers.media.photopicker.PickerFragmentActivity"),
                        ComponentName("com.android.providers.media.module", "com.android.providers.media.photopicker.PickerFragmentActivity")
                    )
                    chooser.putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, excludedComponents)
                    startActivityForResult(chooser, pickImageRequestCode)
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
