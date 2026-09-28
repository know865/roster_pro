package com.example.roster_pro

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.roster/calendar_real"

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
                else -> result.notImplemented()
            }
        }
    }

    // ==================== 通知頻道 ====================

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "上班提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "班次上班前的提醒通知"
                enableVibration(true)
                setShowBadge(true)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // ==================== 精確鬧鐘權限檢查 ====================
    // 因為 AndroidManifest 已宣告 USE_EXACT_ALARM（API 33+）與 SCHEDULE_EXACT_ALARM（API 31-32），
    // 在 API 33+ 上 canScheduleExactAlarms() 會自動回傳 true，無需引導使用者。
    // 在 API 31-32 上 SCHEDULE_EXACT_ALARM 也是自動授予。

    private fun handleCanScheduleExactAlarms(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                result.success(alarmManager.canScheduleExactAlarms())
            } else {
                result.success(true) // API 30 及以下無需此權限
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

            if (alarmMillis == null) {
                result.error("NO_TIME", "alarmMillis is null", null)
                return
            }

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("title", title)
                putExtra("body", body)
                putExtra("requestCode", requestCode)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 因為宣告了 USE_EXACT_ALARM（API 33+ 自動授予）與 SCHEDULE_EXACT_ALARM（API 31-32 自動授予），
            // 大部分情況下 canScheduleExactAlarms() 都會是 true，可直接排精確鬧鐘。
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        // 有精確鬧鐘權限（自動授予）→ 精確鬧鐘
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent
                        )
                    } else {
                        // 極少數情況（例如使用者手動到系統設定把 SCHEDULE_EXACT_ALARM 關閉）
                        // → 降級為非精確鬧鐘，保證功能不中斷
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent
                        )
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Android 6~11：無需精確鬧鐘權限
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent
                    )
                } else {
                    // Android 5 及以下
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent
                    )
                }
            } catch (_: SecurityException) {
                // 保底：若任何精確鬧鐘呼叫被拒 → 用最普通的 set()
                alarmManager.set(AlarmManager.RTC_WAKEUP, alarmMillis, pendingIntent)
            }

            // 記錄 requestCode 以便之後全部取消
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
            // 同時清掉可能殘留的通知
            try {
                val nm = NotificationManagerCompat.from(this)
                for (codeStr in codes) {
                    val code = codeStr.toIntOrNull() ?: continue
                    nm.cancel(code)
                }
            } catch (_: Exception) {}
            result.success(cancelled)
        } catch (e: Exception) {
            result.error("CANCEL_FAIL", e.message, null)
        }
    }

    // ==================== 原有方法（保持不變） ====================

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

// ==================== 鬧鐘觸發接收器 ====================
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "上班提醒"
        val body = intent.getStringExtra("body") ?: ""
        val requestCode = intent.getIntExtra("requestCode", 0)

        val notificationManager = NotificationManagerCompat.from(context)

        // 點擊通知開啟 App
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, MainActivity.ALARM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        try {
            notificationManager.notify(requestCode, builder.build())
        } catch (_: SecurityException) {
            // 沒有通知權限（Android 13+ 的 POST_NOTIFICATIONS），忽略
        }
    }
}
