package com.example.roster_pro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "上班提醒"
        val body = intent.getStringExtra("body") ?: ""
        val requestCode = intent.getIntExtra("requestCode", 0)
        val soundUri = intent.getStringExtra("soundUri")

        // 獲取通知管理器
        val notificationManager = NotificationManagerCompat.from(context)

        // 如果有自訂鈴聲，動態建立一個對應的 NotificationChannel
        val channelId = if (!soundUri.isNullOrEmpty()) {
            createCustomSoundChannel(context, soundUri)
        } else {
            MainActivity.ALARM_CHANNEL_ID
        }

        // 點擊通知開啟 App
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        // 如果沒有使用自訂通道（即使用預設通道），我們手動設定鈴聲
        if (soundUri.isNullOrEmpty()) {
            val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            builder.setSound(defaultSoundUri)
        }

        try {
            notificationManager.notify(requestCode, builder.build())
        } catch (_: SecurityException) {
            // 沒有通知權限（Android 13+ 的 POST_NOTIFICATIONS），忽略
        }
    }

    private fun createCustomSoundChannel(context: Context, soundUri: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "roster_alarm_custom_${soundUri.hashCode()}"
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                channelId,
                "自訂鈴聲提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "使用自訂鈴聲的班次提醒"
                enableVibration(true)
                setShowBadge(true)
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                setSound(Uri.parse(soundUri), audioAttributes)
            }
            nm.createNotificationChannel(channel)
            return channelId
        }
        return MainActivity.ALARM_CHANNEL_ID
    }
}
