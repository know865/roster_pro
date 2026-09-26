package com.example.roster_pro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class RosterWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        writeDebugLog(context, "=== onUpdate: ${appWidgetIds.size} widgets ===")
        // 【問題1 修復】延遲500ms再渲染，避免初次載入字體過大
        Handler(Looper.getMainLooper()).postDelayed({
            for (appWidgetId in appWidgetIds) {
                try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {
                    writeDebugLog(context, "onUpdate error: ${e.message}")
                }
            }
        }, 500)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        writeDebugLog(context, "onAppWidgetOptionsChanged")
        try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {}
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        writeDebugLog(context, "=== onReceive: $action ===")
        if (action == "PREV_MONTH" || action == "NEXT_MONTH" || action == "REFRESH_WIDGET") {
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val thisWidget = android.content.ComponentName(context, RosterWidgetProvider::class.java)
                val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
                val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                var year = prefs.getInt("year", Calendar.getInstance().get(Calendar.YEAR))
                var month = prefs.getInt("month", Calendar.getInstance().get(Calendar.MONTH))
                if (action == "PREV_MONTH") { month--; if (month < 0) { month = 11; year-- } }
                else if (action == "NEXT_MONTH") { month++; if (month > 11) { month = 0; year++ } }
                prefs.edit().putInt("year", year).putInt("month", month).apply()
                writeDebugLog(context, "Month changed to: $year-$month")
                for (appWidgetId in allWidgetIds) {
                    try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {}
                }
            } catch (e: Exception) {
                writeDebugLog(context, "onReceive error: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "RosterWidget"

        private fun writeDebugLog(context: Context, message: String) {
            try {
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
                val line = "[$timestamp][Kotlin] $message\n"
                try {
                    val dir = context.getExternalFilesDir(null)
                    if (dir != null) {
                        if (!dir.exists()) dir.mkdirs()
                        val file = File(dir, "roster_widget_debug.txt")
                        file.appendText(line)
                        if (file.length() > 200 * 1024) file.writeText("[$timestamp] (log reset)\n")
                        return
                    }
                } catch (e: Exception) { Log.e(TAG, "Write to ExternalFiles failed: ${e.message}") }
                try {
                    val downloadDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                    if (downloadDir != null) {
                        if (!downloadDir.exists()) downloadDir.mkdirs()
                        val file = File(downloadDir, "roster_widget_debug.txt")
                        file.appendText(line)
                        return
                    }
                } catch (e: Exception) { Log.e(TAG, "Write to Download failed: ${e.message}") }
                try { val file = File(context.filesDir, "roster_widget_debug.txt"); file.appendText(line) } catch (e: Exception) { Log.e(TAG, "Write to filesDir failed: ${e.message}") }
            } catch (e: Exception) { Log.e(TAG, "writeDebugLog fatal error: ${e.message}") }
        }

        private fun getValueAsDouble(sp: SharedPreferences, key: String, def: Double): Double {
            return try { val v = sp.all[key]; when (v) { null -> def; is Double -> v; is Float -> v.toDouble(); is Long -> v.toDouble(); is Int -> v.toDouble(); is String -> v.toDoubleOrNull() ?: def; else -> def } } catch (e: Exception) { def }
        }

        private fun getFontSizeSafe(sp: SharedPreferences, key: String, def: Double): Double {
            val raw = getValueAsDouble(sp, key, def)
            if (raw <= 0.0) return def
            if (raw <= 500.0) return raw
            try {
                val decoded = java.lang.Double.longBitsToDouble(raw.toLong())
                if (decoded > 0.0 && decoded <= 500.0) return decoded
            } catch (_: Exception) {}
            return def
        }

        private fun getColorSafe(sp: SharedPreferences, key: String, def: Int): Int {
            val raw = sp.all[key] ?: return def
            val candidates = mutableListOf<Long>()
            when (raw) {
                is Int -> candidates.add(raw.toLong())
                is Long -> {
                    candidates.add(raw)
                    try {
                        val decoded = java.lang.Double.longBitsToDouble(raw)
                        if (decoded > 0 && decoded <= Int.MAX_VALUE.toDouble()) candidates.add(decoded.toLong())
                    } catch (_: Exception) {}
                }
                is Double -> {
                    if (raw > 0 && raw <= Int.MAX_VALUE.toDouble()) candidates.add(raw.toLong())
                    try {
                        val decoded = java.lang.Double.longBitsToDouble(raw.toLong())
                        if (decoded > 0 && decoded <= Int.MAX_VALUE.toDouble()) candidates.add(decoded.toLong())
                    } catch (_: Exception) {}
                }
                is Float -> candidates.add(raw.toLong())
                is String -> raw.toLongOrNull()?.let { candidates.add(it) }
            }
            for (c in candidates) {
                val i = c.toInt()
                if ((i ushr 24) != 0) return i
            }
            return def
        }

        private fun isDarkColor(c: Int): Boolean {
            val a = (c ushr 24) and 0xFF
            if (a < 0x60) return true
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            return (0.299 * r + 0.587 * g + 0.114 * b) < 80
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            writeDebugLog(context, "========== Widget Update 開始 ==========")
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            try {
                val widgetPrefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                val homeWidgetPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                val cal = Calendar.getInstance()
                val year = widgetPrefs.getInt("year", cal.get(Calendar.YEAR))
                val month = widgetPrefs.getInt("month", cal.get(Calendar.MONTH))
                val monthNames = arrayOf("1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月")

                // 【問題1 修復】讀取字體大小，若為空或異常則預設為 14.0
                var fontSize = getFontSizeSafe(homeWidgetPrefs, "widgetFontSize", 0.0)
                if (fontSize <= 0.0) fontSize = getFontSizeSafe(flutterPrefs, "flutter.widgetFontSize", 0.0)
                if (fontSize <= 0.0) fontSize = 14.0

                var textColor = getColorSafe(homeWidgetPrefs, "widgetTextColor", 0)
                if (textColor == 0) textColor = getColorSafe(flutterPrefs, "flutter.widgetTextColor", 0)
                if (textColor == 0) textColor = 0xFF333333.toInt()

                var bgColor = getColorSafe(homeWidgetPrefs, "widgetBgColor", 0)
                if (bgColor == 0) bgColor = getColorSafe(flutterPrefs, "flutter.widgetBgColor", 0)
                if (bgColor == 0) bgColor = 0xFFFFFFFF.toInt()

                var todayBgColor = getColorSafe(homeWidgetPrefs, "today_bg", 0)
                if (todayBgColor == 0) todayBgColor = getColorSafe(flutterPrefs, "flutter.today_bg", 0)
                if (todayBgColor == 0 || isDarkColor(todayBgColor)) {
                    todayBgColor = 0xFFBBDEFB.toInt()
                }

                var rosterJsonStr = homeWidgetPrefs.getString("roster_json", "") ?: ""
                if (rosterJsonStr.isEmpty()) rosterJsonStr = flutterPrefs.getString("flutter.roster_json", "{}") ?: "{}"
                var defsJsonStr = homeWidgetPrefs.getString("defs_json", "") ?: ""
                if (defsJsonStr.isEmpty()) defsJsonStr = flutterPrefs.getString("flutter.defs_json", "{}") ?: "{}"
                var lunarJsonStr = homeWidgetPrefs.getString("lunar_json", "") ?: ""
                if (lunarJsonStr.isEmpty()) lunarJsonStr = flutterPrefs.getString("flutter.lunar_json", "{}") ?: "{}"

                val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }
                val defsJson = try { JSONObject(defsJsonStr) } catch (e: Exception) { JSONObject() }
                val lunarJson = try { JSONObject(lunarJsonStr) } catch (e: Exception) { JSONObject() }

                // 設定標題字體大小（使用 1.5 倍，避免過大）
                views.setTextViewText(R.id.tv_month_title, "${year}年${monthNames[month]}")
                views.setTextColor(R.id.tv_month_title, textColor)
                views.setTextViewTextSize(R.id.tv_month_title, TypedValue.COMPLEX_UNIT_SP, (fontSize * 1.5).toFloat())

                val calendar = Calendar.getInstance()
                calendar.set(year, month, 1)
                val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2
                val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                val weekFormat = SimpleDateFormat("ww", Locale.UK)
                val paleTextColor = 0xFFB0B0B0.toInt()
                val todayDrawableId = context.resources.getIdentifier("cell_bg_today", "drawable", context.packageName)

                for (i in 0 until 42) {
                    val dayIndex = i - startOffset + 1
                    val dayTvId = context.resources.getIdentifier("day$i", "id", context.packageName)
                    val shiftTvId = context.resources.getIdentifier("shift$i", "id", context.packageName)
                    val lunarTvId = context.resources.getIdentifier("lunar$i", "id", context.packageName)
                    val cellId = context.resources.getIdentifier("cell$i", "id", context.packageName)
                    if (dayTvId == 0) continue
                    try {
                        val cellCal = Calendar.getInstance()
                        cellCal.set(year, month, dayIndex)
                        val cellYear = cellCal.get(Calendar.YEAR)
                        val cellMonth = cellCal.get(Calendar.MONTH)
                        val cellDay = cellCal.get(Calendar.DAY_OF_MONTH)
                        val isCurrMonth = (cellMonth == month && cellYear == year)

                        val dateStr = String.format("%04d-%02d-%02d", cellYear, cellMonth + 1, cellDay)
                        val shiftCode = rosterJson.optString(dateStr, "")
                        val lunarText = lunarJson.optString(dateStr, "")

                        views.setTextViewText(dayTvId, cellDay.toString())
                        val cellColor = if (isCurrMonth) textColor else paleTextColor
                        views.setTextColor(dayTvId, cellColor)
                        views.setTextViewTextSize(dayTvId, TypedValue.COMPLEX_UNIT_SP, fontSize.toFloat())

                        // 格子背景
                        if (cellId != 0) {
                            if (dateStr == todayStr && isCurrMonth && todayDrawableId != 0) {
                                try { views.setInt(cellId, "setBackgroundResource", todayDrawableId) } catch (e: Exception) {
                                    try { views.setInt(cellId, "setBackgroundColor", todayBgColor) } catch (e2: Exception) {}
                                }
                            } else {
                                try { views.setInt(cellId, "setBackgroundColor", bgColor) } catch (e: Exception) {}
                            }
                        } else {
                            if (dateStr == todayStr && isCurrMonth) {
                                try { views.setInt(dayTvId, "setBackgroundColor", todayBgColor) } catch (e: Exception) {}
                            } else {
                                try { views.setInt(dayTvId, "setBackgroundColor", bgColor) } catch (e: Exception) {}
                            }
                        }

                        // 顯示班次 (非本月日期也顯示)
                        if (shiftTvId != 0) {
                            if (shiftCode.isNotEmpty()) {
                                views.setTextViewText(shiftTvId, shiftCode)
                                views.setTextColor(shiftTvId, 0xFFFFFFFF.toInt())
                                views.setTextViewTextSize(shiftTvId, TypedValue.COMPLEX_UNIT_SP, (fontSize * 0.7).toFloat())
                                var chipColor = 0xFF4CAF50.toInt()
                                val defObj = defsJson.optJSONObject(shiftCode)
                                if (defObj != null) {
                                    val c = defObj.optLong("color", 0).toInt()
                                    if (c != 0) chipColor = c
                                }
                                try { views.setInt(shiftTvId, "setBackgroundColor", chipColor) } catch (e: Exception) {}
                                views.setViewVisibility(shiftTvId, View.VISIBLE)
                            } else {
                                views.setTextViewText(shiftTvId, "")
                                try { views.setInt(shiftTvId, "setBackgroundColor", Color.TRANSPARENT) } catch (e: Exception) {}
                                views.setViewVisibility(shiftTvId, View.INVISIBLE)
                            }
                        }

                        // 顯示農曆
                        if (lunarTvId != 0) {
                            if (lunarText.isNotEmpty()) {
                                views.setTextViewText(lunarTvId, lunarText)
                                views.setTextColor(lunarTvId, 0xFF666666.toInt())
                                views.setTextViewTextSize(lunarTvId, TypedValue.COMPLEX_UNIT_SP, (fontSize * 0.55).toFloat())
                                views.setViewVisibility(lunarTvId, View.VISIBLE)
                            } else {
                                views.setTextViewText(lunarTvId, "")
                                views.setViewVisibility(lunarTvId, View.INVISIBLE)
                            }
                        }

                        val intent = Intent(context, MainActivity::class.java)
                        intent.putExtra("selected_date", dateStr)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        views.setOnClickPendingIntent(dayTvId, PendingIntent.getActivity(context, appWidgetId * 1000 + i, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    } catch (e: Exception) { writeDebugLog(context, "cell $i error: ${e.message}") }
                }

                for (row in 0 until 6) {
                    var rowHasCurrentMonth = false
                    for (col in 0 until 7) {
                        val idx = row * 7 + col
                        val dayIndex = idx - startOffset + 1
                        if (dayIndex in 1..maxDaysInMonth) { rowHasCurrentMonth = true; break }
                    }
                    val rowId = context.resources.getIdentifier("row$row", "id", context.packageName)
                    if (rowId != 0) {
                        views.setViewVisibility(rowId, if (rowHasCurrentMonth) View.VISIBLE else View.GONE)
                    }
                    if (rowHasCurrentMonth) {
                        val weekTvId = context.resources.getIdentifier("week$row", "id", context.packageName)
                        if (weekTvId != 0) {
                            val rowFirstDay = DateTimeUtils.getDateOfIndex(year, month, row * 7, startOffset)
                            if (rowFirstDay != null) {
                                val weekStr = weekFormat.format(rowFirstDay)
                                views.setTextViewText(weekTvId, "W$weekStr")
                                views.setTextColor(weekTvId, 0xFF673AB7.toInt())
                            }
                        }
                    }
                }

                try { views.setInt(R.id.widget_root, "setBackgroundColor", bgColor) } catch (e: Exception) {}

                val prevIntent = Intent(context, RosterWidgetProvider::class.java).setAction("PREV_MONTH")
                views.setOnClickPendingIntent(R.id.btn_prev, PendingIntent.getBroadcast(context, 0, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val nextIntent = Intent(context, RosterWidgetProvider::class.java).setAction("NEXT_MONTH")
                views.setOnClickPendingIntent(R.id.btn_next, PendingIntent.getBroadcast(context, 1, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val refreshIntent = Intent(context, RosterWidgetProvider::class.java).setAction("REFRESH_WIDGET")
                views.setOnClickPendingIntent(R.id.btn_refresh, PendingIntent.getBroadcast(context, 2, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))

                writeDebugLog(context, "✅ Widget 渲染成功 id=$appWidgetId")
            } catch (e: Exception) {
                writeDebugLog(context, "❌ updateAppWidget error: ${e.message}")
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
