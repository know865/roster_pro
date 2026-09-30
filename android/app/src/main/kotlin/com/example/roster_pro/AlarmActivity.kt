package com.example.roster_pro

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.view.animation.AlphaAnimation
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

            // 2. 完全移除背景變暗，讓原生鎖屏桌布 100% 透出
            window.setDimAmount(0f)
            window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)

            // 3. 根佈局全透明（不遮擋桌布）
            val rootLayout = FrameLayout(this).apply {
                setBackgroundColor(Color.TRANSPARENT)
            }

            // 4. 中央懸浮卡片（50% 磨砂半透明）
            val cardLayout = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(24), dp(32), dp(24), dp(32))

                // 50% 透明黑 + 20% 白色細邊框 = 模擬磨砂玻璃質感
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(28).toFloat()
                    setColor(Color.parseColor("#80000000")) // 50% 透明黑
                    setStroke(dp(1), Color.parseColor("#33FFFFFF")) // 20% 白色邊框
                }

                // 陰影
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    elevation = dp(12).toFloat()
                }
            }

            // 5. 標題（白色）
            val titleTv = TextView(this).apply {
                text = intent.getStringExtra("title") ?: "上班提醒"
                setTextColor(Color.WHITE)
                textSize = 22f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(16))
                setTypeface(typeface, Typeface.BOLD)
            }

            // 6. 超大時間提示文字（白色）
            val bodyTv = TextView(this).apply {
                val bodyText = intent.getStringExtra("body") ?: ""
                text = bodyText
                setTextColor(Color.WHITE)
                textSize = 36f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(28))
                setTypeface(typeface, Typeface.BOLD)
                if (bodyText.length > 15) textSize = 28f
                if (bodyText.length > 25) textSize = 22f
            }

            // 7. 停止按鈕（藥丸形狀）
            val stopBtn = Button(this).apply {
                text = "停止響鈴"
                textSize = 20f
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                isAllCaps = false
                gravity = Gravity.CENTER

                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(50).toFloat()
                    setColor(Color.parseColor("#E53935"))
                }

                val params = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(64)
                )
                params.gravity = Gravity.CENTER_HORIZONTAL
                layoutParams = params

                setOnClickListener {
                    stopVibration()
                    val stopIntent = Intent(this@AlarmActivity, AlarmService::class.java).apply {
                        action = AlarmService.ACTION_STOP_ALARM
                    }
                    startService(stopIntent)
                    finish()
                }

                setOnTouchListener { v, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> v.alpha = 0.7f
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> v.alpha = 1.0f
                    }
                    false
                }
            }

            cardLayout.addView(titleTv)
            cardLayout.addView(bodyTv)
            cardLayout.addView(stopBtn)

            // 卡片寬度 85%
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

            // 9. 震動
            startVibration()

        } catch (e: Exception) {
            e.printStackTrace()
            finish()
        }
    }

    private fun startVibration() {
        try {
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (vibrator?.hasVibrator() == true) {
                isVibrating = true
                val pattern = longArrayOf(0, 800, 500)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
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

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVibration()
    }

    override fun onBackPressed() {
        // 防止按返回鍵關閉，必須點擊停止
    }
}
