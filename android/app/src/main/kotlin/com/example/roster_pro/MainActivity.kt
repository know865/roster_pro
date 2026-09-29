package com.example.roster_pro

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaScannerConnection
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.roster/calendar_real"
    private val RINGTONE_CHANNEL = "com.roster/ringtone"
    private var currentRingtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopAlarmService() // App 打開時，自動停止響鈴
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stopAlarmService() // 從通知點擊進入 App 時，自動停止響鈴
    }

    private fun stopAlarmService() {
        try {
            val stopIntent = Intent(this, AlarmService::class.java).apply {
                action = AlarmService.ACTION_STOP_ALARM
            }
            startService(stopIntent)
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCalendars" -> handleGetCalendars(result)
                "scanImage" -> handleScanImage(call.argument<String>("path"), result)
                "requestManageStorage" -> handleRequestManageStorage(result)
                "updateWidget" -> handleUpdateWidget(result)
                "scheduleAlarm" -> handleScheduleAlarm(call, result)
                "cancelAllAlarms" -> handleCancelAllAlarms(result)
                "canScheduleExactAlarms" -> handleCanScheduleExactAlarms(result)
                "deleteAllEventsInCalendar" -> {
                    val calendarId = call.argument<String>("calendarId")
                    if (calendarId == null) result.error("NO_CAL_ID", "Calendar ID is null", null)
                    else handleDeleteAllEvents(calendarId, result)
                }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRingtones" -> handleGetRingtones(result)
                "playRingtone" -> handlePlayRingtone(call.argument<String>("uri"), result)
                "stopRingtone" -> {
                    stopCurrentRingtone()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val channel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "上班提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "班次上班前的提醒通知（鬧鐘模式）"
                enableVibration(true)
                enableLights(true)
                setShowBadge(true)
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttributes)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun handleGetRingtones(result: MethodChannel.Result) {
        try {
            val ringtones = mutableListOf<Map<String, String>>()
            val manager = RingtoneManager(this)
            manager.setType(RingtoneManager.TYPE_ALARM)
            val cursor = manager.cursor
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = manager.getRingtoneUri(cursor.position).toString()
                ringtones.add(mapOf("name" to title, "uri" to uri))
            }
            result.success(ringtones)
        } catch (e: Exception) {
            result.error("GET_RINGTONES_ERROR", e.message, null)
        }
    }

    private fun handlePlayRingtone(uriString: String?, result: MethodChannel.Result) {
        if (uriString == null) {
            result.error("INVALID_URI", "URI is null", null)
            return
        }
        try {
            stopCurrentRingtone()
            val uri = Uri.parse(uriString)
            currentRingtone = RingtoneManager.getRingtone(this, uri)
            currentRingtone?.play()
            result.success(true)
        } catch (e: Exception) {
            result.error("PLAY_RINGTONE_ERROR", e.message, null)
        }
    }

    private fun stopCurrentRingtone() {
        currentRingtone?.stop()
        currentRingtone = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopCurrentRingtone()
    }

    private fun handleCanScheduleExactAlarms(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                result.success(alarmManager.canScheduleExactAlarms())
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleScheduleAlarm(call: MethodCall, result: MethodChannel.Result) {
        try {
            val alarmMillis = call.argument<Long>("alarmMillis")
            val requestCode = call.argument<Int>("requestCode") ?: 0
            val title = call.argument<String>("title") ?: "上班提醒"
            val body = call.argument<String>("body") ?: ""
            val soundUri = call.argument<String>("soundUri")

            if (alarmMillis == null) {
                result.error("NO_TIME", "alarmMillis is null", null)
                return
            }

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java)
            intent.putExtra("title", title)
            intent.putExtra("body", body)
            intent.putExtra("requestCode", requestCode)
            if (soundUri != null && soundUri.isNotEmpty()) {
                intent.putExtra("soundUri", soundUri)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
                }
            } catch (_: SecurityException) {
                alarmManager.set(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
            }

            val prefs = getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE)
            val codes = prefs.getStringSet(ALARM_CODES_KEY, emptySet())?.toMutableSet() ?: mutableSetOf()
            codes.add(requestCode.toString())
            prefs.edit().putStringSet(ALARM_CODES_KEY, codes).apply()

            result.success(true)
        } catch (e: Exception) {
            result.error("ALARM_FAIL", e.message, null)
        }
    }

    private fun handleCancelAllAlarms(result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE)
            val codes = prefs.getStringSet(ALARM_CODES_KEY, emptySet()) ?: emptySet()
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            var cancelled = 0
            for (codeStr in codes) {
                val code = codeStr.toIntOrNull() ?: continue
                val intent = Intent(this, AlarmReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    code,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
                cancelled++
            }
            prefs.edit().remove(ALARM_CODES_KEY).apply()
            result.success(cancelled)
        } catch (e: Exception) {
            result.error("CANCEL_FAIL", e.message, null)
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
            result.error("PERMISSION", "No calendar permission", null)
            return
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
            } else result.success(true)
        } catch (e: Exception) { result.error("STORAGE_FAIL", e.message, null) }
    }

    private fun handleQueryEvents(calendarId: String, startMillis: Long, endMillis: Long, result: MethodChannel.Result) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No read calendar permission", null)
                return
            }
            val events = mutableListOf<Map<String, Any?>>()
            val projection = arrayOf(
                CalendarContract.Events._ID, CalendarContract.Events.TITLE, CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND, CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.CALENDAR_ID, CalendarContract.Events.DELETED
            )
            val selection = "(" + CalendarContract.Events.CALENDAR_ID + " = ?) AND " +
                    "(" + CalendarContract.Events.DTSTART + " < ?) AND " +
                    "((" + CalendarContract.Events.DTEND + " > ?) OR (" + CalendarContract.Events.DTEND + " IS NULL))"
            val selectionArgs = arrayOf(calendarId, endMillis.toString(), startMillis.toString())
            val cursor = contentResolver.query(CalendarContract.Events.CONTENT_URI, projection, selection, selectionArgs, CalendarContract.Events.DTSTART + " ASC")
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
                    if (!it.isNull(deletedIdx) && it.getInt(deletedIdx) == 1) continue
                    val dtStart = it.getLong(dtStartIdx)
                    val dtEnd = if (it.isNull(dtEndIdx)) dtStart else it.getLong(dtEndIdx)
                    events.add(mapOf(
                        "eventId" to it.getLong(idIdx).toString(), "title" to it.getString(titleIdx),
                        "description" to it.getString(descIdx), "startMillis" to dtStart,
                        "endMillis" to dtEnd, "allDay" to (it.getInt(allDayIdx) == 1),
                        "calendarId" to it.getString(calIdIdx)
                    ))
                }
            }
            result.success(events)
        } catch (e: Exception) { result.error("QUERY_FAIL", e.message, null) }
    }

    private fun handleDeleteEvent(calendarId: String, eventId: String, result: MethodChannel.Result) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No write calendar permission", null)
                return
            }
            val eventIdLong = eventId.toLongOrNull()
            if (eventIdLong == null) { result.error("BAD_ID", "eventId is not a number: " + eventId, null); return }
            val checkProjection = arrayOf(CalendarContract.Events.CALENDAR_ID)
            val checkSelection = CalendarContract.Events._ID + " = ?"
            val checkArgs = arrayOf(eventId)
            var belongs = false
            contentResolver.query(CalendarContract.Events.CONTENT_URI, checkProjection, checkSelection, checkArgs, null)?.use { c ->
                if (c.moveToFirst()) { belongs = (c.getString(0) == calendarId) }
            }
            if (!belongs) { result.success(false); return }
            val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventIdLong)
            val rows = contentResolver.delete(eventUri, null, null)
            result.success(rows > 0)
        } catch (e: Exception) { result.error("DELETE_FAIL", e.message, null) }
    }

    private fun handleDeleteAllEvents(calendarId: String, result: MethodChannel.Result) {
        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION", "No write calendar permission", null); return
            }
            val uri = CalendarContract.Events.CONTENT_URI
            val projection = arrayOf(CalendarContract.Events._ID)
            val selection = CalendarContract.Events.CALENDAR_ID + " = ?"
            val selectionArgs = arrayOf(calendarId)
            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
            val eventIds = mutableListOf<Long>()
            cursor?.use { while (it.moveToNext()) { eventIds.add(it.getLong(0)) } }
            val batchSize = 10
            var deleted = 0
            var index = 0
            while (index < eventIds.size) {
                val end = minOf(index + batchSize, eventIds.size)
                for (i in index until end) {
                    val eventUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventIds[i])
                    try { contentResolver.delete(eventUri, null, null); deleted++ } catch (e: Exception) {}
                }
                index = end
                if (index < eventIds.size) { try { Thread.sleep(200) } catch (_: InterruptedException) {} }
            }
            result.success(deleted)
        } catch (e: Exception) { result.error("DELETE_FAIL", e.message, null) }
    }

    companion object {
        const val ALARM_CHANNEL_ID = "roster_alarm_channel"
        const val ALARM_PREFS = "roster_alarm_prefs"
        const val ALARM_CODES_KEY = "alarm_request_codes"
    }
}
