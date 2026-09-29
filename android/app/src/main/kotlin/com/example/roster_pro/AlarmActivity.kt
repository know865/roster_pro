package com.example.roster_pro

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class AlarmActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 關鍵：允許在鎖屏上顯示，並點亮螢幕
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        // 簡單的全屏佈局
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(android.graphics.Color.BLACK)
            gravity = android.view.Gravity.CENTER
        }

        val titleTv = TextView(this).apply {
            text = intent.getStringExtra("title") ?: "上班提醒"
            setTextColor(android.graphics.Color.WHITE)
            textSize = 28f
            gravity = android.view.Gravity.CENTER
        }

        val bodyTv = TextView(this).apply {
            text = intent.getStringExtra("body") ?: ""
            setTextColor(android.graphics.Color.LTGRAY)
            textSize = 20f
            gravity = android.view.Gravity.CENTER
            setPadding(0, 30, 0, 80)
        }

        val stopBtn = Button(this).apply {
            text = "停止響鈴"
            textSize = 24f
            setOnClickListener {
                // 發送停止指令給 Service
                val stopIntent = Intent(this@AlarmActivity, AlarmService::class.java).apply {
                    action = AlarmService.ACTION_STOP_ALARM
                }
                startService(stopIntent)
                finish()
            }
        }

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.CENTER
        }

        layout.addView(titleTv, params)
        layout.addView(bodyTv, params)
        layout.addView(stopBtn, params)

        setContentView(layout)
    }

    override fun onBackPressed() {
        // 防止用家按返回鍵關閉，必須點擊停止
        // super.onBackPressed()
    }
}
