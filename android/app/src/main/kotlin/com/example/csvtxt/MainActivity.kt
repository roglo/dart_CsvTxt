package com.example.csvtxt

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/intent")
            .setMethodCallHandler { call, result ->
          if (call.method == "getInitialUri") {
            val uri = intent?.data
            if (uri == null) {
              result.success(null); return@setMethodCallHandler
            }
            if (uri.scheme == "file") {
                result.success(uri.path)
            } else {
                // content:// → copie dans un fichier temporaire
                val fileName =
                  contentResolver.query(
                    uri, null, null, null, null
                  )?.use { cursor ->
                  val nameIndex = cursor.getColumnIndex(
                    android.provider.OpenableColumns.DISPLAY_NAME
                  )
                  cursor.moveToFirst()
                  cursor.getString(nameIndex)
                } ?: "opened_file"

                val tmpFile = java.io.File(cacheDir, fileName)
                contentResolver.openInputStream(uri)?.use { input ->
                  tmpFile.outputStream().use { output -> input.copyTo(output) }
                }
                result.success(tmpFile.absolutePath)
            }
          }
        }
    }
}