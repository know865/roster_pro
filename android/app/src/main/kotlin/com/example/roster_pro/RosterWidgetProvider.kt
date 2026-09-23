package roster_pro 

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
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

            // 保存當前顯示的月份
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

            for (appWidgetId in allWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    companion object {
        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // 獲取當前顯示的月份 (從 widget 自己的 prefs，預設為當前月)
            val widgetPrefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
            val cal = Calendar.getInstance()
            var year = widgetPrefs.getInt("year", cal.get(Calendar.YEAR))
            var month = widgetPrefs.getInt("month", cal.get(Calendar.MONTH))

            // 更新標題
            val monthNames = arrayOf("1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月")
            views.setTextViewText(R.id.tv_month_title, "${year}年 ${monthNames[month]}")

            // 讀取 Flutter 的 SharedPreferences (注意 Flutter 會加前綴 "flutter.")
            val flutterPrefs: SharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val rosterJsonStr = flutterPrefs.getString("flutter.roster", "{}")
            val rosterJson = try { JSONObject(rosterJsonStr) } catch (e: Exception) { JSONObject() }

            // 計算日曆格子
            val calendar = Calendar.getInstance()
            calendar.set(year, month, 1)
            val firstDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) // 1=Sun, 2=Mon...
            // 將星期一作為第一天 (Monday=1, Sunday=7)
            val startOffset = if (firstDayOfWeek == Calendar.SUNDAY) 6 else firstDayOfWeek - 2

            val maxDaysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
            val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())

            // 獲取 GridLayout
            val gridLayout = views.getViewId(R.id.grid_calendar)

            // 清空 GridLayout (在 RemoteViews 中無法直接清空，我們需要利用索引更新)
            // 為了簡單起見，我們假設 XML 中已經有 42 個 TextView，或者我們動態創建它們。
            // 由於 RemoteViews 不支持動態添加 View，我們必須在 XML 中定義好 42 個 TextView。
            // 這裡我們使用反射/硬編碼的方式來更新它們。
            // 建議：在 XML 中複製 42 個 TextView，id 為 day0 到 day41，這裡我們使用簡化邏輯。

            // 由於直接在 XML 寫 42 個太冗長，我們可以利用自定義的 RemoteViews 或者直接在 XML 寫死。
            // 為了讓你能夠快速運行，我這裡提供一個簡單的邏輯：我們直接在 XML 中放置一個 GridLayout，然後在 Kotlin 中動態添加 TextView (但 RemoteViews 不支持動態添加，所以需要另一種方法)。

            // 修正方案：由於 RemoteViews 的限制，我們無法在運行時動態添加 View。
            // 我們必須在 XML 中預先放置 42 個 TextView (id 從 day0 到 day41)。
            // 為了節省你的時間，我在這裡提供一個循環來更新它們。
            // 你需要在 XML 的 GridLayout 中放入 42 個 TextView，並將它們的 id 設置為 day0, day1, ... day41。

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
                        
                        // 高亮今天
                        if (dateStr == todayStr) {
                            views.setInt(textViewId, "setBackgroundColor", Color.parseColor("#FFF9C4")) // 淺黃色
                        } else {
                            views.setInt(textViewId, "setBackgroundColor", Color.TRANSPARENT)
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
