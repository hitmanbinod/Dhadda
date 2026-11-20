package com.dhadda.expense

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max

/**
 * Camera/gallery capture through system intents: no runtime permission and no
 * Flutter package. Images are decoded down to 1600px long edge and re-encoded
 * as JPEG q80 WITHOUT copying EXIF, then written to app-private files.
 */
class MediaBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var cameraUri: Uri? = null
    private var incomingDir: File? = null

    companion object {
        const val REQ_CAMERA = 0x4D01
        const val REQ_GALLERY = 0x4D02
        private const val MAX_EDGE = 1600
    }

    private fun dir(): File {
        val d = File(activity.applicationInfo.dataDir, "app_flutter/receipts/incoming")
        d.mkdirs()
        incomingDir = d
        return d
    }

    fun takePhoto(result: MethodChannel.Result) {
        val target = File(dir(), "capture-${System.currentTimeMillis()}.jpg")
        cameraUri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            target,
        )
        pending = result
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, cameraUri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQ_CAMERA)
    }

    fun pickImages(result: MethodChannel.Result) {
        pending = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(Intent.createChooser(intent, "Choose photos"), REQ_GALLERY)
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_CAMERA && requestCode != REQ_GALLERY) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(emptyList<String>())
            return true
        }
        try {
            val saved = mutableListOf<String>()
            if (requestCode == REQ_CAMERA) {
                cameraUri?.let { shrink(it, "photo")?.let(saved::add) }
            } else {
                val uris = mutableListOf<Uri>()
                data?.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
                } ?: data?.data?.let(uris::add)
                for ((i, uri) in uris.withIndex()) {
                    shrink(uri, "gallery-$i")?.let(saved::add)
                }
            }
            result.success(saved)
        } catch (e: Exception) {
            result.error("RECEIPT", "${e.message}", null)
        }
        return true
    }

    private fun shrink(uri: Uri, prefix: String): String? {
        val outDir = incomingDir ?: dir()
        val out = File(outDir, "$prefix-${System.currentTimeMillis()}-${(0..9999).random()}.jpg")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        activity.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_EDGE) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = activity.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: return null
        // Compress to a fresh JPEG: no EXIF / location metadata is copied.
        out.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
        bitmap.recycle()
        return out.absolutePath
    }
}
