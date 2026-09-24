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
import java.text.SimpleDateFormat
import java.util.*

class RosterWidgetProvider : AppWidgetProvider() {
    private val TAG = "RosterWidget"

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) { Log.e(TAG, "onUpdate error", e) }
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {}
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
                    try { updateAppWidget(context, appWidgetManager, appWidgetId) } catch (e: Exception) {}
                }
            } catch (e: Exception) { Log.e(TAG, "onReceive error", e) }
        }
    }

    companion object {
        private fun getSafeFloat(sp: SharedPreferences, key: String, def: Float): Float {
            return try { sp.getFloat(key, def) } catch (e: Exception) {
                try { sp.getLong(key, def.toLong()).toFloat() } catch (e2: Exception) {
                    try { sp.getInt(key, def.toInt()).toFloat() } catch (e3: Exception) { def }
                }
            }
        }
        private fun getSafeInt(sp: SharedPreferences, key: String, def: Int): Int {
            return try { sp.getInt(key, def) } catch (e: Exception) {
                try { sp.getLong(key, def.toLong()).toInt() } catch (e2: Exception) { def }
            }
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            try {
                val widgetPrefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                val cal = Calendar.getInstance()
                val year = widgetPrefs.getInt("year", cal.get(Calendar.YEAR))
                val month = widgetPrefs.getInt("month", cal.get(Calendar.MONTH))
                val monthNames = arrayOf("1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月")

                val fp: SharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                // 嘗試多種鍵名，確保讀到
                var fontSize = getSafeFloat(fp, "flutter.widgetFontSize", 0f)
                if (fontSize <= 0f) fontSize = getSafeFloat(fp, "flutter.widget_font_size", 0f)
                if (fontSize <= 0f) fontSize = 55f

                var textColor = getSafeInt(fp, "flutter.widgetTextColor", 0)
                if (textColor == 0) textColor = getSafeInt(fp, "flutter.widget_text_color", 0xFF333333.toInt())
                if (textColor == 0) textColor = 0xFF333333.toInt()

                val bgColor = getSafeInt(fp, "flutter.widgetBgColor", 0xFFFFFFFF.toInt())
                val todayBgColor = getSafeInt(fp, "flutter.today_bg", 0xFFFFF9C4.toInt())

                Log.d(TAG, "Widget Settings -> FontSize: $fontSize, TextColor: $textColor")

                val rosterJsonStr = fp.getString("flutter.roster_json", "{}") ?: "{}"
                val defsJsonStr = fp.getString("flutter.defs_json", "{}") ?: "{}"
                val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }
                val defsJson = try { JSONObject(defsJsonStr) } catch (e: Exception) { JSONObject() }

                views.setTextViewText(R.id.tv_month_title, "${year}年${monthNames[month]}")
                views.setTextColor(R.id.tv_month_title, textColor)
                views.setTextViewTextSize(R.id.tv_month_title, TypedValue.COMPLEX_UNIT_SP, fontSize * 0.8f)

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
                            views.setTextViewTextSize(tvId, TypedValue.COMPLEX_UNIT_SP, fontSize)
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
                    } catch (e: Exception) {}
                }

                try { views.setInt(R.id.widget_root, "setBackgroundColor", bgColor) } catch (e: Exception) {}

                val prevIntent = Intent(context, RosterWidgetProvider::class.java).setAction("PREV_MONTH")
                views.setOnClickPendingIntent(R.id.btn_prev, PendingIntent.getBroadcast(context, 0, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val nextIntent = Intent(context, RosterWidgetProvider::class.java).setAction("NEXT_MONTH")
                views.setOnClickPendingIntent(R.id.btn_next, PendingIntent.getBroadcast(context, 1, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val refreshIntent = Intent(context, RosterWidgetProvider::class.java).setAction("REFRESH_WIDGET")
                views.setOnClickPendingIntent(R.id.btn_refresh, PendingIntent.getBroadcast(context, 2, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget error: ${e.message}", e)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
