package com.example.roster_pro

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.AlphaAnimation
import android.view.animation.Animation
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

class AlarmActivity : Activity() {

    private var vibrator: Vibrator? = null
    private var isVibrating = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            // 1. 鎖屏顯示與點亮螢幕
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

            // 2. 設置半透明背景，讓鎖屏桌布微微透出 (高級感)
            window.setDimAmount(0.6f)
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)

            // 3. 建立根佈局（全螢幕半透明黑）
            val rootLayout = FrameLayout(this).apply {
                setBackgroundColor(Color.parseColor("#A6000000")) // 65% 黑色
            }

            // 4. 建立中央懸浮卡片 (膠囊/1/3屏效果)
            val cardLayout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(24), dp(32), dp(24), dp(32))

                // 圓角背景 + 陰影
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(28).toFloat()
                    setColor(Color.parseColor("#1A1A1A")) // 深灰近黑
                    setStroke(dp(1), Color.parseColor("#333333")) // 細微邊框
                }

                // 陰影
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    elevation = dp(12).toFloat()
                }
            }

            // 5. 頂部圖標 + 標題
            val titleTv = TextView(this).apply {
                text = intent.getStringExtra("title") ?: "上班提醒"
                setTextColor(Color.parseColor("#FF5252")) // 紅色系
                textSize = 22f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(16))
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }

            // 6. 超大時間/核心提示文字
            val bodyTv = TextView(this).apply {
                val bodyText = intent.getStringExtra("body") ?: ""
                text = bodyText
                setTextColor(Color.WHITE)
                textSize = 36f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(28))
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                // 如果文字太長，自動縮小
                if (bodyText.length > 15) textSize = 28f
                if (bodyText.length > 25) textSize = 22f
            }

            // 7. 停止按鈕（藥丸形狀）
            val stopBtn = Button(this).apply {
                text = "停止響鈴"
                textSize = 20f
                setTextColor(Color.WHITE)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                isAllCaps = false
                gravity = Gravity.CENTER

                // 藥丸形狀背景
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(50).toFloat() // 全圓角 = 藥丸
                    setColor(Color.parseColor("#E53935")) // 鮮豔紅
                }

                val params = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(64) // 按鈕高度
                )
                params.gravity = Gravity.CENTER_HORIZONTAL
                layoutParams = params

                // 點擊效果與停止邏輯
                setOnClickListener {
                    stopVibration()
                    val stopIntent = Intent(this@AlarmActivity, AlarmService::class.java).apply {
                        action = AlarmService.ACTION_STOP_ALARM
                    }
                    startService(stopIntent)
                    finish()
                }

                // 按壓反饋 (透明度)
                setOnTouchListener { v, event ->
                    when (event.action) {
                        android.view.MotionEvent.ACTION_DOWN -> v.alpha = 0.7f
                        android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> v.alpha = 1.0f
                    }
                    false
                }
            }

            // 將元件加入卡片
            cardLayout.addView(titleTv)
            cardLayout.addView(bodyTv)
            cardLayout.addView(stopBtn)

            // 設定卡片佔螢幕寬度 85%，高度自適應
            val cardParams = FrameLayout.LayoutParams(
                (resources.displayMetrics.widthPixels * 0.85).toInt(),
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
            }

            rootLayout.addView(cardLayout, cardParams)
            setContentView(rootLayout)

            // 8. 淡入動畫
            val fadeIn = AlphaAnimation(0f, 1f).apply {
                duration = 400
                fillAfter = true
            }
            cardLayout.startAnimation(fadeIn)

            // 9. 開始震動
            startVibration()

        } catch (e: Exception) {
            e.printStackTrace()
            finish()
        }
    }

    // 震動邏輯
    private fun startVibration() {
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (vibrator?.hasVibrator() == true) {
                isVibrating = true
                val pattern = longArrayOf(0, 800, 500) // 震 0.8秒，停 0.5秒
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0)) // 0 = 無限循環
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, 0)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopVibration() {
        try {
            if (isVibrating) {
                vibrator?.cancel()
                isVibrating = false
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // dp 轉 px 工具
    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVibration()
    }

    override fun onBackPressed() {
        // 防止按返回鍵關閉，必須點擊停止
        // super.onBackPressed()
    }
}
