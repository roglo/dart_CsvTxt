package com.example.csvtxt
import android.content.ContentValues
import android.provider.MediaStore
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
            result.success(null)
            return@setMethodCallHandler
          }
          if (uri.scheme == "file") {
            result.success(uri.path)
          } else {
            val fileName =
              contentResolver
                .query(uri, null, null, null, null)?.use { cursor ->
                  val nameIndex =
                    cursor.getColumnIndex(
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

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/mediastore")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "lexiconExists" -> {
            val uri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID)
            val selection =
              "${MediaStore.Files.FileColumns.RELATIVE_PATH} = ? AND " +
              "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ?"
            val args = arrayOf("Documents/CsvTxt/", "lexicon.txt")
            val cursor =
              contentResolver.query(uri, projection, selection, args, null)
            val existe = (cursor?.count ?: 0) > 0
            cursor?.close()
            result.success(existe)
          }
          "getApkPath" -> {
            result.success(applicationInfo.sourceDir)
          }
          "getApkInstallDate" -> {
            val pm = packageManager
            val info = pm.getPackageInfo(packageName, 0)
            result.success(info.lastUpdateTime)  // en millisecondes
          }
          "createLexicon" -> {
            val bytes = call.arguments as ByteArray
            val collectionUri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID)
            val selection =
              "${MediaStore.Files.FileColumns.RELATIVE_PATH} = ? AND " +
              "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ?"
            val args = arrayOf("Documents/CsvTxt/", "lexicon.txt")
            val cursor =
              contentResolver.query(
                collectionUri, projection, selection, args, null
              )
            if (cursor != null && cursor.moveToFirst()) {
              val id =
                cursor.getLong(
                  cursor.getColumnIndexOrThrow(
                    MediaStore.Files.FileColumns._ID
                  )
                )
              val existingUri = MediaStore.Files.getContentUri("external", id)
              contentResolver.openOutputStream(
                existingUri, "wt"
              )?.use { it.write(bytes) }
              cursor.close()
            } else {
              cursor?.close()
              val values = ContentValues().apply {
                put(MediaStore.Files.FileColumns.DISPLAY_NAME, "lexicon.txt")
                put(MediaStore.Files.FileColumns.MIME_TYPE, "text/plain")
                put(
                  MediaStore.Files.FileColumns.RELATIVE_PATH,
                  "Documents/CsvTxt/"
                )
              }
              val newUri = contentResolver.insert(collectionUri, values)!!
              contentResolver.openOutputStream(newUri)?.use { it.write(bytes) }
            }
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
  }
}
