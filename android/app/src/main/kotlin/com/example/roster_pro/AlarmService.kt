package com.example.roster_pro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmService : Service() {
    private var mediaPlayer: MediaPlayer? = null

    companion object {
        const val ACTION_START_ALARM = "com.example.roster_pro.START_ALARM"
        const val ACTION_STOP_ALARM = "com.example.roster_pro.STOP_ALARM"
        const val CHANNEL_ID = "roster_alarm_foreground_channel"
        const val NOTIFICATION_ID = 9999
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_ALARM) {
            stopAlarmAndSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra("title") ?: "上班提醒"
        val body = intent?.getStringExtra("body") ?: ""
        val soundUri = intent?.getStringExtra("soundUri")
        val requestCode = intent?.getIntExtra("requestCode", 0) ?: 0

        startForeground(NOTIFICATION_ID, buildNotification(title, body, requestCode))
        playAlarmSound(soundUri)

        return START_STICKY
    }

    private fun playAlarmSound(soundUri: String?) {
        try {
            val uri = if (soundUri.isNullOrEmpty()) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            } else {
                Uri.parse(soundUri)
            }
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM) // 關鍵：無視靜音/震動，強制從鬧鐘音訊流播放
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmService, uri)
                isLooping = true // 關鍵：循環播放直到使用者按停
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun buildNotification(title: String, body: String, requestCode: Int): android.app.Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "鬧鐘響鈴",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "班次上班鬧鐘響鈴"
                setSound(null, null) // 聲音由 MediaPlayer 播放
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC // 允許鎖屏顯示
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        // 1. 停止按鈕的 PendingIntent（直接在通知欄點擊停止）
        val stopIntent = Intent(this, AlarmService::class.java).apply {
            action = ACTION_STOP_ALARM
        }
        val stopPendingIntent = PendingIntent.getService(
            this, requestCode + 10000, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2. 全屏 Intent（關鍵：讓鎖屏直接彈出 AlarmActivity 畫面）
        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("requestCode", requestCode)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this, requestCode + 20000, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 3. 點擊通知內容的 PendingIntent
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = PendingIntent.getActivity(
            this, requestCode, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM) // 標記為鬧鐘類別
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // 鎖屏顯示
            .setContentIntent(contentPendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "停止響鈴", stopPendingIntent) // 通知欄的停止按鈕
            .setFullScreenIntent(fullScreenPendingIntent, true) // 關鍵：鎖屏全屏彈出
            .setOngoing(true) // 防止被滑掉
            .build()
    }

    private fun stopAlarmAndSelf() {
        mediaPlayer?.let {
            if (it.isPlaying) it.stop()
            it.release()
        }
        mediaPlayer = null
        stopForeground(true)
        NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaPlayer?.let {
            if (it.isPlaying) it.stop()
            it.release()
        }
        mediaPlayer = null
    }
}
