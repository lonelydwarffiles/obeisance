package com.obeisance.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ObeisanceForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Obeisance is Active")
            .setContentText("You are currently monitored by your Controller.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Persistent status for active Obeisance monitoring."
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "obeisance_leash"
        private const val CHANNEL_NAME = "Obeisance Active"
        private const val NOTIFICATION_ID = 9031
    }
}
