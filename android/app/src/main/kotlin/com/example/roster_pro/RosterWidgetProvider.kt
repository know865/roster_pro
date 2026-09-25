package com.example.roster_pro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class RosterWidgetProvider : AppWidgetProvider() {
    private val TAG = "RosterWidget"

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        writeDebugLog(context, "=== onUpdate: ${appWidgetIds.size} widgets ===")
        for (appWidgetId in appWidgetIds) {
            try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {
                writeDebugLog(context, "onUpdate error: ${e.message}")
            }
        }
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
        // ===== 寫入除錯檔案（多路徑嘗試，只要有一個成功即可）=====
        private fun writeDebugLog(context: Context, message: String) {
            try {
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
                val line = "[$timestamp][Kotlin] $message\n"

                // 路徑 1：App 專屬外部目錄（不需要權限，最穩定）
                try {
                    val dir = context.getExternalFilesDir(null)
                    if (dir != null) {
                        if (!dir.exists()) dir.mkdirs()
                        val file = File(dir, "roster_widget_debug.txt")
                        file.appendText(line)
                        if (file.length() > 200 * 1024) {
                            file.writeText("[$timestamp] (log reset)\n")
                        }
                        return
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Write to ExternalFiles failed: ${e.message}")
                }

                // 路徑 2：公共 Download 目錄
                try {
                    val downloadDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                    if (downloadDir != null) {
                        if (!downloadDir.exists()) downloadDir.mkdirs()
                        val file = File(downloadDir, "roster_widget_debug.txt")
                        file.appendText(line)
                        return
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Write to Download failed: ${e.message}")
                }

                // 路徑 3：App 內部儲存
                try {
                    val file = File(context.filesDir, "roster_widget_debug.txt")
                    file.appendText(line)
                } catch (e: Exception) {
                    Log.e(TAG, "Write to filesDir failed: ${e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "writeDebugLog fatal error: ${e.message}")
            }
        }

        // ===== 通用解析：任何型別都能轉成 Double =====
        private fun getValueAsDouble(sp: SharedPreferences, key: String, def: Double): Double {
            return try {
                val v = sp.all[key]
                when (v) {
                    null -> def
                    is Double -> v
                    is Float -> v.toDouble()
                    is Long -> v.toDouble()
                    is Int -> v.toDouble()
                    is String -> v.toDoubleOrNull() ?: def
                    else -> def
                }
            } catch (e: Exception) { def }
        }

        // ===== 通用解析：任何型別都能轉成 Int (修復 Double 溢出問題) =====
        private fun getValueAsInt(sp: SharedPreferences, key: String, def: Int): Int {
            return try {
                val v = sp.all[key]
                when (v) {
                    null -> def
                    is Int -> v
                    is Long -> v.toInt()
                    is Double -> v.toLong().toInt()  // 【關鍵修復】先轉 Long 再轉 Int，防止大數值溢出
                    is Float -> v.toInt()
                    is String -> v.toDoubleOrNull()?.toLong()?.toInt() ?: v.toIntOrNull() ?: def
                    else -> def
                }
            } catch (e: Exception) { def }
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

                // 優先讀取 HomeWidgetPreferences，其次讀取 FlutterSharedPreferences
                var fontSize = getValueAsDouble(homeWidgetPrefs, "widgetFontSize", 0.0)
                if (fontSize <= 0.0) fontSize = getValueAsDouble(flutterPrefs, "flutter.widgetFontSize", 0.0)
                if (fontSize <= 0.0) fontSize = 55.0

                var textColor = getValueAsInt(homeWidgetPrefs, "widgetTextColor", 0)
                if (textColor == 0) textColor = getValueAsInt(flutterPrefs, "flutter.widgetTextColor", 0)
                if (textColor == 0) textColor = 0xFF333333.toInt()

                var bgColor = getValueAsInt(homeWidgetPrefs, "widgetBgColor", 0)
                if (bgColor == 0) bgColor = getValueAsInt(flutterPrefs, "flutter.widgetBgColor", 0)
                if (bgColor == 0) bgColor = 0xFFFFFFFF.toInt()

                var todayBgColor = getValueAsInt(homeWidgetPrefs, "today_bg", 0)
                if (todayBgColor == 0) todayBgColor = getValueAsInt(flutterPrefs, "flutter.today_bg", 0)
                if (todayBgColor == 0) todayBgColor = 0xFFFFF9C4.toInt()

                writeDebugLog(context, "讀取成功 - FontSize: $fontSize, TextColor: 0x${Integer.toHexString(textColor)}")
                writeDebugLog(context, "BgColor: 0x${Integer.toHexString(bgColor)}, TodayBg: 0x${Integer.toHexString(todayBgColor)}")

                val rosterJsonStr = flutterPrefs.getString("flutter.roster_json", "{}") ?: "{}"
                val defsJsonStr = flutterPrefs.getString("flutter.defs_json", "{}") ?: "{}"
                val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }
                val defsJson = try { JSONObject(defsJsonStr) } catch (e: Exception) { JSONObject() }

                views.setTextViewText(R.id.tv_month_title, "${year}年${monthNames[month]}")
                views.setTextColor(R.id.tv_month_title, textColor)
                views.setTextViewTextSize(R.id.tv_month_title, TypedValue.COMPLEX_UNIT_SP, (fontSize * 0.8).toFloat())

                val calendar = Calendar.getInstance()
                calendar.set(year, month, 1)
                val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2
                val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

                for (i in 0 until 42) {
                    val dayIndex = i - startOffset + 1
                    val tvId = context.resources.getIdentifier("day$i", "id", context.packageName)
                    if (tvId == 0) continue
                    try {
                        if (dayIndex in 1..maxDaysInMonth) {
                            val dateStr = String.format("%04d-%02d-%02d", year, month + 1, dayIndex)
                            val shiftCode = rosterJson.optString(dateStr, "")
                            var displayText = dayIndex.toString()
                            if (shiftCode.isNotEmpty()) displayText = "$dayIndex\n$shiftCode"
                            views.setTextViewText(tvId, displayText)
                            views.setTextColor(tvId, textColor)
                            views.setTextViewTextSize(tvId, TypedValue.COMPLEX_UNIT_SP, fontSize.toFloat())
                            views.setViewVisibility(tvId, View.VISIBLE)

                            var bg = bgColor
                            if (shiftCode.isNotEmpty()) {
                                val defObj = defsJson.optJSONObject(shiftCode)
                                if (defObj != null) {
                                    val c = defObj.optLong("color", 0).toInt()
                                    if (c != 0) {
                                        val r = (Color.red(c) * 0.3 + 255 * 0.7).toInt()
                                        val g = (Color.green(c) * 0.3 + 255 * 0.7).toInt()
                                        val b = (Color.blue(c) * 0.3 + 255 * 0.7).toInt()
                                        bg = Color.rgb(r, g, b)
                                    }
                                }
                            }
                            if (dateStr == todayStr) bg = todayBgColor
                            try { views.setInt(tvId, "setBackgroundColor", bg) } catch (e: Exception) {}

                            val intent = Intent(context, MainActivity::class.java)
                            intent.putExtra("selected_date", dateStr)
                            views.setOnClickPendingIntent(tvId, PendingIntent.getActivity(context, appWidgetId * 1000 + i, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                        } else {
                            views.setTextViewText(tvId, "")
                            views.setViewVisibility(tvId, View.INVISIBLE)
                        }
                    } catch (e: Exception) {
                        writeDebugLog(context, "cell $i error: ${e.message}")
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
