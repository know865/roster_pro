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

    override fun onEnabled(context: Context?) {
        super.onEnabled(context)
        Log.d(TAG, "=== onEnabled ===")
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        Log.d(TAG, "=== onUpdate: ${appWidgetIds.size} widgets ===")
        for (appWidgetId in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                Log.e(TAG, "onUpdate error: ${e.message}", e)
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        } catch (e: Exception) {
            Log.e(TAG, "onAppWidgetOptionsChanged error: ${e.message}", e)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        Log.d(TAG, "=== onReceive: $action ===")
        if (action == "PREV_MONTH" || action == "NEXT_MONTH" || action == "REFRESH_WIDGET") {
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val thisWidget = android.content.ComponentName(context, RosterWidgetProvider::class.java)
                val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
                val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                var year = prefs.getInt("year", Calendar.getInstance().get(Calendar.YEAR))
                var month = prefs.getInt("month", Calendar.getInstance().get(Calendar.MONTH))
                if (action == "PREV_MONTH") {
                    month--
                    if (month < 0) { month = 11; year-- }
                } else if (action == "NEXT_MONTH") {
                    month++
                    if (month > 11) { month = 0; year++ }
                }
                prefs.edit().putInt("year", year).putInt("month", month).apply()
                Log.d(TAG, "Month changed to: $year-$month")
                for (appWidgetId in allWidgetIds) {
                    try {
                        updateAppWidget(context, appWidgetManager, appWidgetId)
                    } catch (e: Exception) {
                        Log.e(TAG, "receive update error", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "onReceive error", e)
            }
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            try {
                // 讀取當前顯示的年月
                val widgetPrefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                val cal = Calendar.getInstance()
                val year = widgetPrefs.getInt("year", cal.get(Calendar.YEAR))
                val month = widgetPrefs.getInt("month", cal.get(Calendar.MONTH))
                val monthNames = arrayOf("1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月")

                // 讀取 Flutter 傳來的設定
                val fp: SharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val widgetFontSize = fp.getFloat("flutter.widgetFontSize", 11f)
                val widgetTextColor = fp.getLong("flutter.widgetTextColor", 0xFF333333).toInt()
                val widgetBgColor = fp.getLong("flutter.widgetBgColor", 0xFFFFFFFF).toInt()
                val todayBgColor = fp.getLong("flutter.today_bg", 0xFFFFF9C4).toInt()

                // 讀取排更資料
                val rosterJsonStr = fp.getString("flutter.roster_json", "{}") ?: "{}"
                val defsJsonStr = fp.getString("flutter.defs_json", "{}") ?: "{}"
                Log.d(TAG, "rosterJson length: ${rosterJsonStr.length}")
                Log.d(TAG, "defsJson length: ${defsJsonStr.length}")

                val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }
                val defsJson = try { JSONObject(defsJsonStr) } catch (e: Exception) { JSONObject() }

                // 更新標題
                views.setTextViewText(R.id.tv_month_title, "${year}年${monthNames[month]}")
                views.setTextColor(R.id.tv_month_title, widgetTextColor)

                // 計算日曆格子
                val calendar = Calendar.getInstance()
                calendar.set(year, month, 1)
                val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
                val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2
                val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
                val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

                // 更新 42 格
                for (i in 0 until 42) {
                    val dayIndex = i - startOffset + 1
                    val tvId = context.resources.getIdentifier("day$i", "id", context.packageName)
                    if (tvId == 0) continue
                    try {
                        if (dayIndex in 1..maxDaysInMonth) {
                            val dateStr = String.format("%04d-%02d-%02d", year, month + 1, dayIndex)
                            val shiftCode = rosterJson.optString(dateStr, "")
                            var displayText = dayIndex.toString()
                            if (shiftCode.isNotEmpty()) {
                                displayText = "$dayIndex\n$shiftCode"
                            }
                            views.setTextViewText(tvId, displayText)
                            views.setTextColor(tvId, widgetTextColor)
                            views.setTextViewTextSize(tvId, TypedValue.COMPLEX_UNIT_SP, widgetFontSize)
                            views.setViewVisibility(tvId, View.VISIBLE)

                            // 計算背景色
                            var bgColor = widgetBgColor
                            if (shiftCode.isNotEmpty()) {
                                val defObj = defsJson.optJSONObject(shiftCode)
                                if (defObj != null) {
                                    val c = defObj.optLong("color", 0).toInt()
                                    if (c != 0) {
                                        val r = (Color.red(c) * 0.3 + 255 * 0.7).toInt()
                                        val g = (Color.green(c) * 0.3 + 255 * 0.7).toInt()
                                        val b = (Color.blue(c) * 0.3 + 255 * 0.7).toInt()
                                        bgColor = Color.rgb(r, g, b)
                                    }
                                }
                            }
                            // 今天高亮
                            if (dateStr == todayStr) {
                                bgColor = todayBgColor
                            }
                            try {
                                views.setInt(tvId, "setBackgroundColor", bgColor)
                            } catch (e: Exception) {
                                Log.e(TAG, "setBackgroundColor cell $i error")
                            }

                            // 點擊打開 App
                            val intent = Intent(context, MainActivity::class.java)
                            intent.putExtra("selected_date", dateStr)
                            val pi = PendingIntent.getActivity(
                                context, i, intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            )
                            views.setOnClickPendingIntent(tvId, pi)
                        } else {
                            views.setTextViewText(tvId, "")
                            views.setViewVisibility(tvId, View.INVISIBLE)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "update cell $i error: ${e.message}")
                    }
                }

                // 設定根背景
                try {
                    views.setInt(R.id.widget_root, "setBackgroundColor", widgetBgColor)
                } catch (e: Exception) {
                    Log.e(TAG, "set root bg error")
                }

                // 按鈕 PendingIntent
                val prevIntent = Intent(context, RosterWidgetProvider::class.java).setAction("PREV_MONTH")
                views.setOnClickPendingIntent(
                    R.id.btn_prev,
                    PendingIntent.getBroadcast(context, 0, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )
                val nextIntent = Intent(context, RosterWidgetProvider::class.java).setAction("NEXT_MONTH")
                views.setOnClickPendingIntent(
                    R.id.btn_next,
                    PendingIntent.getBroadcast(context, 1, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )
                val refreshIntent = Intent(context, RosterWidgetProvider::class.java).setAction("REFRESH_WIDGET")
                views.setOnClickPendingIntent(
                    R.id.btn_refresh,
                    PendingIntent.getBroadcast(context, 2, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                )

                Log.d(TAG, "Widget update SUCCESS for id=$appWidgetId")
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget OUTER error: ${e.message}", e)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
