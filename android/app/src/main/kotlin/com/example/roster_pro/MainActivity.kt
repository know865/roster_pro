package com.example.roster_pro

import android.Manifest
import android.appwidget.AppWidgetManager
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
                "updateWidget" -> handleUpdateWidget(result)
                "deleteAllEventsInCalendar" -> {
                    val calendarId = call.argument<String>("calendarId")
                    if (calendarId == null) result.error("NO_CAL_ID", "Calendar ID is null", null)
                    else handleDeleteAllEvents(calendarId, result)
                }
                // ✅ 新增：原生查詢事件（繞過 device_calendar 的 Samsung bug）
                "queryEvents" -> {
                    val calendarId = call.argument<String>("calendarId")
                    val startMillis = call.argument<Number>("startMillis")?.toLong()
                    val endMillis = call.argument<Number>("endMillis")?.toLong()
                    if (calendarId == null || startMillis == null || endMillis == null) {
                        result.error("BAD_ARGS", "calendarId/startMillis/endMillis required", null)
                    } else {
                        handleQueryEvents(calendarId, startMillis, endMillis, result)
                    }
                }
                // ✅ 新增：原生刪除單一事件
                "deleteEvent" -> {
                    val calendarId = call.argument<String>("calendarId")
                    val eventId = call.argument<String>("eventId")
                    if (calendarId == null || eventId == null) {
                        result.error("BAD_ARGS", "calendarId/eventId required", null)
                    } else {
                        handleDeleteEvent(calendarId, eventId, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleUpdateWidget(result: MethodChannel.Result) {
        try {
            val appWidgetManager = AppWidgetManager.getInstance(this)
            val thisWidget = android.content.ComponentName(this, RosterWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            for (appWidgetId in allWidgetIds) {
                RosterWidgetProvider.updateAppWidget(this, appWidgetManager, appWidgetId)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("UPDATE_FAIL", e.message, null)
        }
    }

    private fun handleGetCalendars(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION", "No calendar permission", null); return
        }
        val calendars = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE
        )
        val cursor = contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)
        cursor?.use {
            while (it.moveToNext()) {
                val id = it.getLong(0).toString()
                val displayName = it.getString(1) ?: "Unnamed"
                val accountName = it.getString(2) ?: ""
                val accountType = it.getString(3) ?: ""
                val isGoogle = accountName.contains("gmail") || accountType.contains("google") || accountName.contains("google")
                calendars.add(mapOf(
                    "id" to id, "displayName" to displayName,
                    "accountName" to accountName, "accountType" to accountType,
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
            MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf("image/jpeg", "image/jpg", "image/png")) { _, uri ->
                result.success(uri?.toString() ?: path)
            }
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
            } else result.success(true)
        } catch (e: Exception) { result.error("STORAGE_FAIL", e.message, null) }
    }

    /**
     * ✅ 新增：原生查詢指定日曆在時間範圍內的事件
     * 回傳 List<Map>，每筆包含：
     *   eventId, title, description, startMillis, endMillis, allDay, calendarId
     */
    private fun handleQueryEvents(
        calendarId: String,
        startMillis: Long,
        endMillis: Long,
        result: MethodChannel.Result
    ) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No read calendar permission", null); return
            }

            val events = mutableListOf<Map<String, Any?>>()
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.CALENDAR_ID,
                CalendarContract.Events.DELETED
            )
            // 只查詢該日曆 + 時間範圍重疊的事件
            // (DTEND > start) AND (DTSTART < end)
            // 有些事件 DTEND 為 null（例如純開始時間），退而用 DTSTART 判斷
            val selection = "(${CalendarContract.Events.CALENDAR_ID} = ?) AND " +
                    "(${CalendarContract.Events.DTSTART} < ?) AND " +
                    "((${CalendarContract.Events.DTEND} > ?) OR (${CalendarContract.Events.DTEND} IS NULL))"
            val selectionArgs = arrayOf(calendarId, endMillis.toString(), startMillis.toString())

            val cursor = contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                "${CalendarContract.Events.DTSTART} ASC"
            )

            cursor?.use {
                val idIdx = it.getColumnIndexOrThrow(CalendarContract.Events._ID)
                val titleIdx = it.getColumnIndexOrThrow(CalendarContract.Events.TITLE)
                val descIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)
                val dtStartIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
                val dtEndIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                val allDayIdx = it.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)
                val calIdIdx = it.getColumnIndexOrThrow(CalendarContract.Events.CALENDAR_ID)
                val deletedIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DELETED)

                while (it.moveToNext()) {
                    // 跳過已刪除（deleted = 1）的殘留
                    if (!it.isNull(deletedIdx) && it.getInt(deletedIdx) == 1) continue

                    val dtStart = it.getLong(dtStartIdx)
                    val dtEnd = if (it.isNull(dtEndIdx)) dtStart else it.getLong(dtEndIdx)

                    events.add(mapOf(
                        "eventId" to it.getLong(idIdx).toString(),
                        "title" to it.getString(titleIdx),
                        "description" to it.getString(descIdx),
                        "startMillis" to dtStart,
                        "endMillis" to dtEnd,
                        "allDay" to (it.getInt(allDayIdx) == 1),
                        "calendarId" to it.getString(calIdIdx)
                    ))
                }
            }
            result.success(events)
        } catch (e: Exception) {
            result.error("QUERY_FAIL", e.message, null)
        }
    }

    /**
     * ✅ 新增：原生刪除單一事件（使用 CalendarContract）
     * 回傳 Boolean，true 表示刪除成功
     */
    private fun handleDeleteEvent(
        calendarId: String,
        eventId: String,
        result: MethodChannel.Result
    ) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No write calendar permission", null); return
            }

            val eventIdLong = eventId.toLongOrNull()
            if (eventIdLong == null) {
                result.error("BAD_ID", "eventId is not a number: $eventId", null); return
            }

            // 安全檢查：確認該事件真的屬於指定日曆，避免誤刪其他日曆的事件
            val checkProjection = arrayOf(CalendarContract.Events.CALENDAR_ID)
            val checkSelection = "${CalendarContract.Events._ID} = ?"
            val checkArgs = arrayOf(eventId)
            var belongs = false
            contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                checkProjection,
                checkSelection,
                checkArgs,
                null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val calId = c.getString(0)
                    belongs = (calId == calendarId)
                }
            }
            if (!belongs) {
                result.success(false); return
            }

            val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventIdLong)
            val rows = contentResolver.delete(eventUri, null, null)
            result.success(rows > 0)
        } catch (e: Exception) {
            result.error("DELETE_FAIL", e.message, null)
        }
    }

    /**
     * ⚠️ 已棄用：Dart 側已不再呼叫此方法
     * 保留僅為相容舊版本。此方法會刪除日曆上所有事件（含個人行程），請勿使用。
     */
    private fun handleDeleteAllEvents(calendarId: String, result: MethodChannel.Result) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No write calendar permission", null); return
            }
            val projection = arrayOf(CalendarContract.Events._ID)
            val selection = "${CalendarContract.Events.CALENDAR_ID} = ?"
            val selectionArgs = arrayOf(calendarId)
            val cursor = contentResolver.query(CalendarContract.Events.CONTENT_URI, projection, selection, selectionArgs, null)
            val eventIds = mutableListOf<Long>()
            cursor?.use { while (it.moveToNext()) eventIds.add(it.getLong(0)) }

            val batchSize = 10
            var deleted = 0
            var index = 0
            while (index < eventIds.size) {
                val end = minOf(index + batchSize, eventIds.size)
                for (i in index until end) {
                    val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventIds[i])
                    try { contentResolver.delete(eventUri, null, null); deleted++ } catch (_: Exception) {}
                }
                index = end
                if (index < eventIds.size) try { Thread.sleep(200) } catch (_: InterruptedException) {}
            }
            result.success(deleted)
        } catch (e: Exception) { result.error("DELETE_FAIL", e.message, null) }
    }
}
