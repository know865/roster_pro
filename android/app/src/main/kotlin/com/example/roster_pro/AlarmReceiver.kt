package com.example.roster_pro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "上班提醒"
        val body = intent.getStringExtra("body") ?: ""
        val requestCode = intent.getIntExtra("requestCode", 0)
        val soundUri = intent.getStringExtra("soundUri")

        val serviceIntent = Intent(context, AlarmService::class.java).apply {
            action = AlarmService.ACTION_START_ALARM
            putExtra("title", title)
            putExtra("body", body)
            putExtra("requestCode", requestCode)
            putExtra("soundUri", soundUri)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
