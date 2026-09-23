package com.example.roster_pro // <--- 如果你的包名不同，請替換這裡

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class RosterWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action == "PREV_MONTH" || action == "NEXT_MONTH" || action == "REFRESH_WIDGET") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = android.content.ComponentName(context, RosterWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

            val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
            var year = prefs.getInt("year", Calendar.getInstance().get(Calendar.YEAR))
            var month = prefs.getInt("month", Calendar.getInstance().get(Calendar.MONTH)) // 0-11

            if (action == "PREV_MONTH") {
                month--
                if (month < 0) { month = 11; year-- }
            } else if (action == "NEXT_MONTH") {
                month++
                if (month > 11) { month = 0; year++ }
            }

            prefs.edit().putInt("year", year).putInt("month", month).apply()

            for (appWidgetId in allWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // 獲取當前顯示的月份 (優先讀取 widget 自己記住的年月，預設為當前月)
            val widgetPrefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
            val cal = Calendar.getInstance()
            val year = widgetPrefs.getInt("year", cal.get(Calendar.YEAR))
            val month = widgetPrefs.getInt("month", cal.get(Calendar.MONTH)) // 0-11

            // 更新標題
            val monthNames = arrayOf("1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月")
            views.setTextViewText(R.id.tv_month_title, "${year}年 ${monthNames[month]}")

            // 讀取 Flutter 傳來的數據
            // 注意：Flutter 在 Android 原生存儲 SharedPreferences 時會加上 "flutter." 前綴
            val flutterPrefs: SharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val rosterJsonStr = flutterPrefs.getString("flutter.roster_json", "{}")
            val defsJsonStr = flutterPrefs.getString("flutter.defs_json", "{}")
            
            // 讀取今日高亮顏色 (從 Flutter 傳過來的 int)
            val todayBgColor = flutterPrefs.getLong("flutter.today_bg", 0xFFFFF9C4).toInt()
            val todayBorderColor = flutterPrefs.getLong("flutter.today_border", 0xFFFF9800).toInt()

            val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }
            val defsJson = try { JSONObject(defsJsonStr) } catch (e: Exception) { JSONObject() }

            // 計算日曆格子
            val calendar = Calendar.getInstance()
            calendar.set(year, month, 1)
            val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) // 1=Sun, 2=Mon...
            // 將星期一作為第一天 (Monday=1, Sunday=7)
            val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2

            val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
            val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

            for (i in 0 until 42) {
                val dayIndex = i - startOffset + 1
                val textViewId = context.resources.getIdentifier("day$i", "id", context.packageName)
                
                if (textViewId != 0) {
                    if (dayIndex in 1..maxDaysInMonth) {
                        // 這是本月的日期
                        val dateStr = String.format("%04d-%02d-%02d", year, month + 1, dayIndex)
                        val shiftCode = rosterJson.optString(dateStr, "")
                        
                        var displayText = dayIndex.toString()
                        if (shiftCode.isNotEmpty()) {
                            displayText = "$dayIndex\n$shiftCode"
                        }
                        
                        views.setTextViewText(textViewId, displayText)
                        views.setTextColor(textViewId, Color.parseColor("#333333"))
                        views.setViewVisibility(textViewId, View.VISIBLE)

                        // 如果有班次，嘗試根據班次顏色設定背景色 (可選)
                        if (shiftCode.isNotEmpty()) {
                            val defObj = defsJson.optJSONObject(shiftCode)
                            if (defObj != null) {
                                val colorInt = defObj.optLong("color", 0).toInt()
                                // 將原色調淡一點作為背景
                                val r = (Color.red(colorInt) * 0.3 + 255 * 0.7).toInt()
                                val g = (Color.green(colorInt) * 0.3 + 255 * 0.7).toInt()
                                val b = (Color.blue(colorInt) * 0.3 + 255 * 0.7).toInt()
                                views.setInt(textViewId, "setBackgroundColor", Color.rgb(r, g, b))
                            }
                        } else {
                            views.setInt(textViewId, "setBackgroundColor", Color.TRANSPARENT)
                        }

                        // 高亮今天
                        if (dateStr == todayStr) {
                            views.setInt(textViewId, "setBackgroundColor", todayBgColor)
                        }

                        // 點擊日期打開 App
                        val intent = Intent(context, MainActivity::class.java) // 請確保 MainActivity 是你的入口
                        intent.putExtra("selected_date", dateStr)
                        val pendingIntent = PendingIntent.getActivity(context, i, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        views.setOnClickPendingIntent(textViewId, pendingIntent)

                    } else {
                        // 非本月的日期，隱藏或顯示空白
                        views.setTextViewText(textViewId, "")
                        views.setViewVisibility(textViewId, View.INVISIBLE)
                    }
                }
            }

            // 設置按鈕的 PendingIntent
            val prevIntent = Intent(context, RosterWidgetProvider::class.java).setAction("PREV_MONTH")
            val prevPendingIntent = PendingIntent.getBroadcast(context, 0, prevIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.btn_prev, prevPendingIntent)

            val nextIntent = Intent(context, RosterWidgetProvider::class.java).setAction("NEXT_MONTH")
            val nextPendingIntent = PendingIntent.getBroadcast(context, 1, nextIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.btn_next, nextPendingIntent)

            val refreshIntent = Intent(context, RosterWidgetProvider::class.java).setAction("REFRESH_WIDGET")
            val refreshPendingIntent = PendingIntent.getBroadcast(context, 2, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.btn_refresh, refreshPendingIntent)

            // 更新 Widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
