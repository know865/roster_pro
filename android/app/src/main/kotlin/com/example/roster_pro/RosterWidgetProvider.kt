package com.example.roster_pro

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
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
        Handler(Looper.getMainLooper()).postDelayed({
            for (appWidgetId in appWidgetIds) {
                try { updateAppWidget(context, appWidgetManager, appWidgetId) }
                catch (e: Exception) { writeDebugLog(context, "onUpdate error: ${e.message}") }
            }
        }, 500)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (_: Exception) {}
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
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
                for (appWidgetId in allWidgetIds) {
                    try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
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
                } catch (_: Exception) {}
                try { val file = File(context.filesDir, "roster_widget_debug.txt"); file.appendText(line) } catch (_: Exception) {}
            } catch (_: Exception) {}
        }

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
            } catch (_: Exception) { def }
        }

        private fun getFontSizeSafe(sp: SharedPreferences, key: String, def: Double): Double {
            val raw = getValueAsDouble(sp, key, def)
            if (raw <= 0.0 || raw.isNaN()) return def
            if (raw in 8.0..30.0) return raw
            try {
                val decoded = java.lang.Double.longBitsToDouble(raw.toLong())
                if (decoded in 8.0..30.0) return decoded
            } catch (_: Exception) {}
            return def
        }

        private fun getColorSafe(sp: SharedPreferences, key: String, def: Int): Int {
            val raw = sp.all[key] ?: return def
            val result = when (raw) {
                is Int -> raw
                is Long -> raw.toInt()
                is String -> raw.toLongOrNull()?.toInt() ?: def
                is Double -> raw.toInt()
                is Float -> raw.toInt()
                else -> def
            }
            return if ((result ushr 24) != 0) result else def
        }

        private fun dpToPx(context: Context, dp: Int): Int {
            return (dp * context.resources.displayMetrics.density).toInt()
        }

        // 動態生成帶有立體感的圓角膠囊 Bitmap
        private fun createRoundedRectBitmap(context: Context, width: Int, height: Int, color: Int, radius: Float): Bitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint().apply {
                isAntiAlias = true
                this.color = color
            }
            val rectF = RectF(0f, 0f, width.toFloat(), height.toFloat())
            canvas.drawRoundRect(rectF, radius, radius, paint)

            // 頂部高光 (模擬立體感)
            val highlightPaint = Paint().apply {
                isAntiAlias = true
                this.color = 0x55FFFFFF // 33% 白色
                style = Paint.Style.STROKE
                strokeWidth = dpToPx(context, 1).toFloat()
            }
            canvas.drawRoundRect(rectF, radius, radius, highlightPaint)

            // 底部陰影
            val shadowPaint = Paint().apply {
                isAntiAlias = true
                this.color = 0x55000000 // 33% 黑色
                style = Paint.Style.STROKE
                strokeWidth = dpToPx(context, 1).toFloat()
            }
            val shadowRect = RectF(0f, 1f, width.toFloat(), height.toFloat())
            canvas.drawRoundRect(shadowRect, radius, radius, shadowPaint)

            return bitmap
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
                val monthNames = arrayOf("1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月")

                var fontSize = getFontSizeSafe(homeWidgetPrefs, "widgetFontSize", 0.0)
                if (fontSize <= 0.0 || fontSize.isNaN()) fontSize = getFontSizeSafe(flutterPrefs, "flutter.widgetFontSize", 0.0)
                if (fontSize <= 0.0 || fontSize.isNaN()) fontSize = 14.0

                // 強制背景為白色 (需求 1)
                val bgColor = 0xFFFFFFFF.toInt()
                val todayBgColor = 0xFFFFFFFF.toInt()

                var rosterJsonStr = homeWidgetPrefs.getString("roster_json", "") ?: ""
                if (rosterJsonStr.isEmpty()) rosterJsonStr = flutterPrefs.getString("flutter.roster_json", "{}") ?: "{}"
                var defsJsonStr = homeWidgetPrefs.getString("defs_json", "") ?: ""
                if (defsJsonStr.isEmpty()) defsJsonStr = flutterPrefs.getString("flutter.defs_json", "{}") ?: "{}"
                var lunarJsonStr = homeWidgetPrefs.getString("lunar_json", "") ?: ""
                if (lunarJsonStr.isEmpty()) lunarJsonStr = flutterPrefs.getString("flutter.lunar_json", "{}") ?: "{}"

                val rosterJson = try { JSONObject(rosterJsonStr) } catch (_: Exception) { JSONObject() }
                val defsJson = try { JSONObject(defsJsonStr) } catch (_: Exception) { JSONObject() }
                val lunarJson = try { JSONObject(lunarJsonStr) } catch (_: Exception) { JSONObject() }

                views.setTextViewText(R.id.tv_month_title, "${year}年${monthNames[month]}")
                views.setTextColor(R.id.tv_month_title, 0xFF333333.toInt())
                views.setTextViewTextSize(R.id.tv_month_title, TypedValue.COMPLEX_UNIT_SP, (fontSize * 1.5).toFloat())

                val calendar = Calendar.getInstance()
                calendar.set(year, month, 1)
                val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2
                val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                val weekFormat = SimpleDateFormat("ww", Locale.UK)
                val paleTextColor = 0xFFB0B0B0.toInt()

                for (i in 0 until 42) {
                    try {
                        val dayIndex = i - startOffset + 1
                        val dayTvId = context.resources.getIdentifier("day$i", "id", context.packageName)
                        val shiftTvId = context.resources.getIdentifier("shift$i", "id", context.packageName)
                        val shiftBgId = context.resources.getIdentifier("shift_bg$i", "id", context.packageName)
                        val lunarTvId = context.resources.getIdentifier("lunar$i", "id", context.packageName)
                        val cellId = context.resources.getIdentifier("cell$i", "id", context.packageName)
                        if (dayTvId == 0) continue

                        val cellCal = Calendar.getInstance()
                        cellCal.set(year, month, dayIndex)
                        val cellYear = cellCal.get(Calendar.YEAR)
                        val cellMonth = cellCal.get(Calendar.MONTH)
                        val cellDay = cellCal.get(Calendar.DAY_OF_MONTH)
                        val isCurrMonth = (cellMonth == month && cellYear == year)

                        val dateStr = String.format("%04d-%02d-%02d", cellYear, cellMonth + 1, cellDay)
                        val shiftCode = rosterJson.optString(dateStr, "")
                        val lunarText = lunarJson.optString(dateStr, "")

                        // 日期字體
                        views.setTextViewText(dayTvId, cellDay.toString())
                        val cellColor = if (isCurrMonth) 0xFF000000.toInt() else paleTextColor
                        views.setTextColor(dayTvId, cellColor)
                        views.setTextViewTextSize(dayTvId, TypedValue.COMPLEX_UNIT_SP, fontSize.toFloat())

                        // 背景全白
                        if (cellId != 0) {
                            views.setInt(cellId, "setBackgroundColor", bgColor)
                        } else {
                            views.setInt(dayTvId, "setBackgroundColor", bgColor)
                        }

                        // 班次膠囊設計 (需求 2, 3, 4)
                        if (shiftTvId != 0 && shiftBgId != 0) {
                            if (shiftCode.isNotEmpty()) {
                                views.setTextViewText(shiftTvId, shiftCode)
                                var chipColor = 0xFF4CAF50.toInt()
                                val defObj = defsJson.optJSONObject(shiftCode)
                                if (defObj != null) {
                                    val c = defObj.optLong("color", 0).toInt()
                                    if (c != 0) chipColor = c
                                }

                                // 字體放大 2 倍，若字數大於 2 則縮小防溢出
                                var shiftTextSize = fontSize * 2.0
                                if (shiftCode.length > 2) {
                                    shiftTextSize = fontSize * 1.2
                                }
                                views.setTextViewTextSize(shiftTvId, TypedValue.COMPLEX_UNIT_SP, shiftTextSize.toFloat())

                                // 動態生成立體膠囊背景
                                val width = dpToPx(context, 12 + shiftCode.length * 14)
                                val height = dpToPx(context, 26)
                                val bitmap = createRoundedRectBitmap(context, width, height, chipColor, dpToPx(context, 10).toFloat())
                                views.setImageViewBitmap(shiftBgId, bitmap)

                                views.setViewVisibility(shiftBgId, View.VISIBLE)
                                views.setViewVisibility(shiftTvId, View.VISIBLE)
                            } else {
                                views.setViewVisibility(shiftBgId, View.GONE)
                                views.setViewVisibility(shiftTvId, View.GONE)
                            }
                        }

                        // 農曆字體
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

                        // ======== 修改點：點擊整個格子進入 App ========
                        val intent = Intent(context, MainActivity::class.java).apply {
                            action = "com.example.roster_pro.OPEN_DATE_${appWidgetId}_$i"
                            putExtra("selected_date", dateStr)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        val requestCode = (appWidgetId % 10000) * 100 + i
                        val pi = PendingIntent.getActivity(
                            context, requestCode, intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        // 優先綁定整個 cellId，若無則退回 dayTvId
                        if (cellId != 0) {
                            views.setOnClickPendingIntent(cellId, pi)
                        } else {
                            views.setOnClickPendingIntent(dayTvId, pi)
                        }
                        // ==============================================

                    } catch (e: Exception) { writeDebugLog(context, "cell $i error: ${e.message}") }
                }

                for (row in 0 until 6) {
                    var rowHasCurrentMonth = false
                    for (col in 0 until 7) {
                        val dayIndex = row * 7 + col - startOffset + 1
                        if (dayIndex in 1..maxDaysInMonth) { rowHasCurrentMonth = true; break }
                    }
                    val rowId = context.resources.getIdentifier("row$row", "id", context.packageName)
                    if (rowId != 0) views.setViewVisibility(rowId, if (rowHasCurrentMonth) View.VISIBLE else View.GONE)
                    if (rowHasCurrentMonth) {
                        val weekTvId = context.resources.getIdentifier("week$row", "id", context.packageName)
                        if (weekTvId != 0) {
                            val rowFirstDayCal = Calendar.getInstance()
                            rowFirstDayCal.set(year, month, 1)
                            rowFirstDayCal.add(Calendar.DAY_OF_MONTH, row * 7 - startOffset)
                            views.setTextViewText(weekTvId, "W${weekFormat.format(rowFirstDayCal.time)}")
                            views.setTextColor(weekTvId, 0xFF673AB7.toInt())
                        }
                    }
                }

                try { views.setInt(R.id.widget_root, "setBackgroundColor", bgColor) } catch (_: Exception) {}

                try {
                    val rootIntent = Intent(context, MainActivity::class.java).apply {
                        action = "com.example.roster_pro.OPEN_FROM_WIDGET_$appWidgetId"
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    views.setOnClickPendingIntent(
                        R.id.widget_root,
                        PendingIntent.getActivity(
                            context, appWidgetId, rootIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                    )
                } catch (_: Exception) {}

                views.setOnClickPendingIntent(R.id.btn_prev, PendingIntent.getBroadcast(context, 0, Intent(context, RosterWidgetProvider::class.java).setAction("PREV_MONTH"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                views.setOnClickPendingIntent(R.id.btn_next, PendingIntent.getBroadcast(context, 1, Intent(context, RosterWidgetProvider::class.java).setAction("NEXT_MONTH"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                views.setOnClickPendingIntent(R.id.btn_refresh, PendingIntent.getBroadcast(context, 2, Intent(context, RosterWidgetProvider::class.java).setAction("REFRESH_WIDGET"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))

                writeDebugLog(context, "✅ Widget 渲染成功 id=$appWidgetId")
            } catch (e: Exception) { writeDebugLog(context, "❌ updateAppWidget error: ${e.message}") }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
