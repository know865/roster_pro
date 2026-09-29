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
    private val RINGTONE_CHANNEL = "com.roster/ringtone"
    private var currentRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel()

        // 日曆與鬧鐘的 Channel
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
                else -> result.notImplemented()
            }
        }

        // 鈴聲的 Channel
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

    // ==================== 通知頻道（關鍵修改：真鬧鐘體驗） ====================

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 關鍵：使用 USAGE_ALARM，即使手機靜音/震動，鬧鐘依然會響
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
                // 關鍵：設定系統預設鬧鐘鈴聲 + 鬧鐘音訊屬性
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttributes)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // ==================== 鈴聲處理 ====================

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

    // ==================== 精確鬧鐘權限檢查 ====================

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

    // ==================== 鬧鐘排程 ====================

    private fun handleScheduleAlarm(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
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
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("title", title)
                putExtra("body", body)
                putExtra("requestCode", requestCode)
                putExtra("soundUri", soundUri)
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

    // ==================== 原有方法 ====================

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

    companion object {
        const val ALARM_CHANNEL_ID = "roster_alarm_channel"
        const val ALARM_PREFS = "roster_alarm_prefs"
        const val ALARM_CODES_KEY = "alarm_request_codes"
    }
}
