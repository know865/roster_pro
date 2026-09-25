package com.example.roster_pro

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.roster/calendar_real"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCalendars" -> handleGetCalendars(result)
                "scanImage" -> handleScanImage(call.argument<String>("path"), result)
                "requestManageStorage" -> handleRequestManageStorage(result)
                "deleteAllEventsInCalendar" -> {
                    val calendarId = call.argument<String>("calendarId")
                    if (calendarId == null) {
                        result.error("NO_CAL_ID", "Calendar ID is null", null)
                    } else {
                        handleDeleteAllEvents(calendarId, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleGetCalendars(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION", "No calendar permission", null)
            return
        }
        val calendars = mutableListOf<Map<String, Any?>>()
        val uri = CalendarContract.Calendars.CONTENT_URI
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE
        )
        val cursor = contentResolver.query(uri, projection, null, null, null)
        cursor?.use {
            while (it.moveToNext()) {
                val id = it.getLong(0).toString()
                val displayName = it.getString(1) ?: "Unnamed"
                val accountName = it.getString(2) ?: ""
                val accountType = it.getString(3) ?: ""
                val isGoogle = accountName.contains("gmail") || accountType.contains("google") || accountName.contains("google")
                calendars.add(mapOf(
                    "id" to id,
                    "displayName" to displayName,
                    "accountName" to accountName,
                    "accountType" to accountType,
                    "isGoogle" to isGoogle
                ))
            }
        }
        result.success(calendars)
    }

    private fun handleScanImage(path: String?, result: MethodChannel.Result) {
        if (path == null) { result.error("NO_PATH", "Path is null", null); return }
        try {
            val file = File(path)
            if (!file.exists()) { result.error("NO_FILE", "File does not exist: $path", null); return }
            MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf("image/jpeg", "image/jpg", "image/png")) { _, uri -> result.success(uri?.toString() ?: path) }
        } catch (e: Exception) { result.error("SCAN_FAIL", e.message, null) }
    }

    private fun handleRequestManageStorage(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (!Environment.isExternalStorageManager()) {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    result.success(false)
                    return
                }
                result.success(true)
            } else { result.success(true) }
        } catch (e: Exception) { result.error("STORAGE_FAIL", e.message, null) }
    }

    // 【核心】分批删除，每批 10 条，绕过 Android 系统的批量删除安全限制
    private fun handleDeleteAllEvents(calendarId: String, result: MethodChannel.Result) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No write calendar permission", null)
                return
            }

            val uri = CalendarContract.Events.CONTENT_URI
            val projection = arrayOf(CalendarContract.Events._ID)
            val selection = "${CalendarContract.Events.CALENDAR_ID} = ?"
            val selectionArgs = arrayOf(calendarId)

            // 先查出所有事件 ID
            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
            val eventIds = mutableListOf<Long>()
            cursor?.use {
                while (it.moveToNext()) {
                    eventIds.add(it.getLong(0))
                }
            }

            // 分批删除，每批 10 条
            val batchSize = 10
            var deleted = 0
            var index = 0
            while (index < eventIds.size) {
                val end = minOf(index + batchSize, eventIds.size)
                for (i in index until end) {
                    val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventIds[i])
                    try {
                        contentResolver.delete(eventUri, null, null)
                        deleted++
                    } catch (e: Exception) {
                        // 忽略个别失败
                    }
                }
                index = end
                // 每删完一批，等 200ms，让系统喘口气，避免触发上限弹窗
                if (index < eventIds.size) {
                    try { Thread.sleep(200) } catch (_: InterruptedException) {}
                }
            }

            result.success(deleted)
        } catch (e: Exception) {
            result.error("DELETE_FAIL", e.message, null)
        }
    }
}
